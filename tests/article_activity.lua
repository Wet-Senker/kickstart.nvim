local activity = require 'article_activity'
local notifications = require 'texttools_notify'
local log = require 'workflow_log'
local preferences = vim.fn.tempname() .. '/activity.json'
activity.setup { preferences = preferences }

local function article(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '-' .. name .. '.md')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', name, '', 'Mijn eigen tekst.' })
  vim.bo[buf].filetype = 'markdown'
  return buf
end
local function panel()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'texttools_activity' then return win end
  end
end
local function wait_for(predicate, message) assert(vim.wait(1000, predicate, 10), message) end
local function text(win) return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n') end
local function key(win, lhs)
  vim.api.nvim_win_call(win, function() vim.fn.maparg(lhs, 'n', false, true).callback() end)
end
local function pause()
  vim.wait(30, function() return false end)
end

local a, b = article 'ZwartsluisBruist', article 'Ander artikel'
vim.api.nvim_set_current_buf(a)
local editor = vim.api.nvim_get_current_win()
local original = vim.api.nvim_buf_get_lines(a, 0, -1, false)
local tick = vim.api.nvim_buf_get_changedtick(a)
vim.api.nvim_win_set_cursor(editor, { 3, 4 })
wait_for(panel, 'strook ontbreekt')
assert(vim.api.nvim_get_current_win() == editor and vim.api.nvim_win_get_cursor(editor)[2] == 4, 'focus/cursor verplaatst')
assert(vim.api.nvim_win_get_height(panel()) == 2, 'compacte strook is niet twee regels hoog')
assert(vim.wo[panel()].winblend == 0 and vim.wo[panel()].wrap, 'strook is transparant of breekt tekst niet af')
assert(vim.bo[vim.api.nvim_win_get_buf(panel())].buftype == 'nofile', 'strook staat in artikelbestand')
assert(activity.panel_visible(a), 'zichtbare strook krijgt dubbele statusbalk')

local tasks = {}
for index = 1, 4 do
  tasks[index] = log.start(a, 'AI · Taak ' .. index)
end
wait_for(function() return vim.wo[panel()].winbar:find('Bezig:', 1, true) end, 'vaste proceskop ontbreekt')
assert(vim.api.nvim_win_get_height(panel()) == 2, 'processtart veranderde artikelruimte')
for index = 1, 8 do
  notifications.workflow('Mijlpaal ' .. index, nil, { buf = a })
end
wait_for(function() return text(panel()):find('Mijlpaal 8', 1, true) end, 'laatste resultaat ontbreekt')
assert(vim.wo[panel()].winbar:find('Taak 1', 1, true), 'resultaat verdrong actieve taak')
key(panel(), 'q')
wait_for(function() return not panel() end, 'q sluit tijdens werk niet echt')
assert(activity.statusline(a):find('4 taken', 1, true), 'verborgen strook verloor processtatus')
pause()
assert(not panel(), 'actieve taak heropende gesloten strook')
activity.toggle()
wait_for(panel, 'strook heropende niet')
for _, task in ipairs(tasks) do
  log.finish(task, 'succeeded')
end
wait_for(function() return not vim.wo[panel()].winbar:find('Bezig:', 1, true) end, 'afgelopen taak bleef staan')
assert(not text(panel()):find('geslaagd', 1, true), 'exitcode werd als geaccepteerd resultaat getoond')

notifications.workflow('Technisch detail', nil, { buf = a, kind = 'success', detail = true })
pause()
assert(text(panel()):find('Mijlpaal 8', 1, true), 'technisch detail verdrong resultaat')
assert(vim.api.nvim_buf_get_changedtick(a) == tick and vim.deep_equal(original, vim.api.nvim_buf_get_lines(a, 0, -1, false)), 'artikeltekst gewijzigd')

-- Leespositie en actieve kop blijven onafhankelijk, ook bij afkappen op 100.
activity.expand()
wait_for(function() return text(panel()):find('Mijlpaal 1', 1, true) end, 'geschiedenis ontbreekt')
local pane = panel()
for index = 1, 100 do
  notifications.workflow('Begrensd ' .. index, nil, { buf = a })
end
wait_for(function() return text(pane):find('Begrensd 100', 1, true) end, 'geschiedenis ververst niet')
vim.api.nvim_set_current_win(pane)
vim.api.nvim_win_set_cursor(pane, { 20, 0 })
vim.cmd 'normal! zt'
local read_line = vim.api.nvim_get_current_line()
local first = log.start(a, 'AI · Herschrijven')
notifications.workflow('Nieuwe gebeurtenis', nil, { buf = a })
wait_for(function() return text(pane):find('Nieuwe gebeurtenis', 1, true) end, 'nieuw resultaat ontbreekt')
assert(vim.api.nvim_get_current_line() == read_line, 'begrensde geschiedenis verschoof tijdens teruglezen')
assert(vim.wo[pane].winbar:find('Herschrijven', 1, true), 'scrollen verborg lopende taak')
assert(vim.api.nvim_get_current_win() == pane, 'verversen nam focus over')
assert(#activity.snapshot(a).entries == 100, 'sessiegeheugen onbegrensd')
log.finish(first, 'succeeded')

-- Meldingen blijven bij hun bron, ook over een callback/schedule-grens.
vim.api.nvim_set_current_win(editor)
local native_system, reply, launches = vim.system, nil, 0
vim.system = function(_, options, done)
  assert(not options.texttools_activity, 'UI-optie lekte naar vim.system')
  launches = launches + 1
  reply = done
  return { kill = function() end }
end
notifications.system({ 'gemockte-taak' }, { text = true }, function()
  notifications.schedule(function() notifications.notify('Resultaat voor A', vim.log.levels.WARN) end)
end)
assert(next(activity.snapshot(a).tasks), 'ongetraceerd subprocess is niet zichtbaar')
vim.api.nvim_set_current_buf(b)
reply { code = 0 }
wait_for(function() return activity.snapshot(a).entries[#activity.snapshot(a).entries].message == 'Resultaat voor A' end, 'callback verloor bron')
assert(next(activity.snapshot(a).tasks) == nil, 'subprocess bleef hangen')
wait_for(function() return activity.panel_visible(b) end, 'strook volgde artikel niet')
assert(not text(panel()):find('Resultaat voor A', 1, true), 'melding lekte naar ander artikel')
assert(launches == 1, 'extra subprocess gestart')
vim.system = native_system

-- Geen wijzigingen in vensterindeling tijdens een dialoog.
local modal_buf = vim.api.nvim_create_buf(false, true)
local modal = vim.api.nvim_open_win(modal_buf, true, { relative = 'editor', width = 30, height = 3, row = 2, col = 2 })
notifications.workflow('Achtergrond', nil, { buf = a })
pause()
assert(vim.api.nvim_get_current_win() == modal, 'melding onderbrak dialoog')
vim.api.nvim_win_close(modal, true)
local late = notifications.bind(a, function()
  notifications.schedule(function() notifications.notify('Niet naar B!', vim.log.levels.ERROR) end)
end)
vim.api.nvim_buf_delete(a, { force = true })
late()
pause()
assert(not vim.inspect(activity.snapshot(b)):find('Niet naar B!', 1, true), 'verdwenen bron werd vervangen door B')
assert(not pcall(notifications.bind(b, function() error 'testfout' end)))
notifications.notify('Huidige bron B', vim.log.levels.INFO)
assert(activity.snapshot(b).entries[#activity.snapshot(b).entries].message == 'Huidige bron B', 'callbackcontext lekte')

-- Fout mag heropenen; gelezen is niet hetzelfde als domeinherstel.
wait_for(panel, 'paneel B ontbreekt')
activity.toggle()
wait_for(function() return not panel() end, 'sluiten mislukt')
assert(vim.json.decode(table.concat(vim.fn.readfile(preferences), '\n')).visible == false, 'voorkeur niet bewaard')
notifications.workflow('Upload mislukt.', vim.log.levels.ERROR, { buf = b })
wait_for(panel, 'nieuwe fout niet zichtbaar')
assert(vim.api.nvim_get_current_win() == editor, 'fout nam focus over')
key(panel(), 'a')
assert(not activity.snapshot(b).attention and next(activity.snapshot(b).issues), 'gelezen werd als opgelost verwijderd')
local b_panel = panel()
vim.cmd 'tabnew'
local c = article 'Derde artikel'
vim.api.nvim_set_current_buf(c)
-- Handmatig openen is nodig: de opgeslagen voorkeur was verborgen.
activity.toggle()
wait_for(panel, 'nieuwe tab kreeg geen paneel')
assert(panel() ~= b_panel, 'tabs delen venster')
notifications.workflow('Alleen voor B', nil, { buf = b })
pause()
assert(not text(panel()):find('Alleen voor B', 1, true), 'andere tab vervuild')
vim.cmd 'tabclose'
wait_for(function() return panel() == b_panel end, 'tabclose sloot ander paneel')
assert(text(b_panel):find('Alleen voor B', 1, true), 'achtergrondmelding verloren')
vim.api.nvim_win_close(editor, true)
activity.toggle()
wait_for(function() return not panel() end, 'laatste paneel bleef hangen')
assert(vim.api.nvim_get_current_buf() == b, 'verborgen bron verloren')
print 'article activity: OK'
