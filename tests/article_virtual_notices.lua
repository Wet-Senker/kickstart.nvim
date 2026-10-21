-- Read-only en ongestructureerde bronnen behouden de virtuele fallback.
local activity = require 'article_activity'
local notices = require 'article_notices'
local preference_path = vim.fn.tempname() .. '/activity.json'
vim.fn.mkdir(vim.fn.fnamemodify(preference_path, ':h'), 'p')
vim.fn.writefile({ vim.json.encode { version = 2, visible = true, expanded = false } }, preference_path)
activity.setup { preferences = preference_path }
local function article()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '---', 'newspaper: {}', '---', '', 'e: B', 'c:', '',
    '=== ARTIKEL ===', '', 'Kop', '', 'Mijn tekst.',
  })
  vim.bo[buf].readonly = true
  return buf
end
local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, notices.namespace, 0, -1, { details = true })
end
local function text(buf)
  local lines = {}
  for _, mark in ipairs(marks(buf)) do
    for _, row in ipairs(mark[4].virt_lines) do
      local line = ''
      for _, chunk in ipairs(row) do line = line .. chunk[1] end
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, '\n')
end
local function wait(test) assert(vim.wait(1000, test, 5), 'aandachtregels bleven hangen') end
local a = article()
local original = vim.api.nvim_buf_get_lines(a, 0, -1, false)
local tick, undo = vim.api.nvim_buf_get_changedtick(a), vim.fn.undotree().seq_cur
local cursor, win = vim.api.nvim_win_get_cursor(0), vim.api.nvim_get_current_win()
activity.record(a, 'Fotocredit ontbreekt. Vul c: in vóór verzending.', vim.log.levels.WARN, { action = 'Fotocredit' })
wait(function() return #marks(a) == 1 end)
assert(marks(a)[1][2] == 7 and marks(a)[1][4].virt_lines_above, 'melding staat niet tussen instellingen en artikel')
assert(text(a):find('Vul c: in vóór verzending.', 1, true), 'vervolgstap ontbreekt')
assert(vim.api.nvim_get_current_win() == win and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor), 'melding nam focus/cursor over')
assert(not activity.panel_visible(a), 'waarschuwing opende een apart venster')
assert(vim.api.nvim_buf_get_changedtick(a) == tick and vim.fn.undotree().seq_cur == undo, 'melding wijzigde de revisie of undo')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(a, 0, -1, false), original), 'melding staat in de artikeltekst')
local path = vim.fn.tempname() .. '.md'
vim.api.nvim_buf_set_name(a, path)
vim.cmd 'silent write!'
vim.bo[a].readonly = true
assert(vim.deep_equal(vim.fn.readfile(path), original), 'virtuele melding werd opgeslagen')

-- Een gelezen markering in de geschiedenis verstopt een onopgelost punt niet.
activity.toggle()
wait(function() return activity.panel_visible(a) end)
for _, pane in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
  if vim.bo[vim.api.nvim_win_get_buf(pane)].filetype == 'texttools_activity' then
    vim.api.nvim_win_call(pane, function() vim.fn.maparg('a', 'n', false, true).callback() end)
  end
end
wait(function() return text(a):find('Fotocredit ontbreekt', 1, true) end)
activity.toggle()

-- Bestaande extmarks schuiven mee, ook wanneer een grens geheel wordt vervangen.
vim.api.nvim_buf_set_lines(a, 4, 4, false, { 'prio: 2' })
wait(function() return marks(a)[1][2] == 8 end)
vim.api.nvim_buf_set_lines(a, 8, 9, false, { 'Nieuwe kopregel', '', '=== ARTIKEL ===' })
wait(function() return marks(a)[1][2] == 10 end)

-- Andere acties lossen het punt niet op; een bijpassende hercontrole wel.
activity.record(a, 'Tekstcontrole afgerond.', nil, { action = 'Tekstcontrole', kind = 'success' })
assert(text(a):find('Fotocredit ontbreekt', 1, true))
activity.record(a, 'Fotocredit gecontroleerd.', nil, { action = 'Fotocredit', kind = 'success' })
wait(function() return #marks(a) == 0 end)

-- Ook verborgen bronnen krijgen hun eigen melding; niet het toevallige artikel.
local b = article()
activity.record(a, 'Verzending niet gestart. Druk opnieuw <leader>aw.', nil, { attention = true, action = 'Verzenden' })
wait(function() return #marks(a) == 1 end)
assert(#marks(b) == 0 and vim.api.nvim_get_current_buf() == b, 'aandacht lekte naar een ander artikel')

-- Brede Unicode-tekst en lange paden blijven binnen een smal artikelvenster.
vim.o.columns = 32
activity.record(b, string.rep('Coördinatie café ✓ ', 30) .. '\nVul c: in en druk <leader>aw.', vim.log.levels.WARN, { action = 'Foto' })
wait(function() return #marks(b) == 1 end)
for _, line in ipairs(vim.split(text(b), '\n', { plain = true })) do
  assert(vim.fn.strdisplaywidth(line) <= 28, 'uitleg werd rechts afgesneden: ' .. line)
end
assert(text(b):find('<leader>kl.', 1, true), 'lange uitleg heeft geen zichtbare leesroute')

-- Een oude import zonder grens krijgt geen verzonnen artikelstructuur.
local raw = vim.api.nvim_create_buf(true, false)
vim.bo[raw].readonly = true
vim.api.nvim_buf_set_lines(raw, 0, -1, false, { 'Ruwe import' })
activity.record(raw, 'Controleer de import en kies een rubriek met <leader>kt.', vim.log.levels.WARN)
wait(function() return #marks(raw) == 1 end)
assert(marks(raw)[1][2] == 0)
assert(not marks(raw)[1][4].virt_lines_above, 'aandacht boven bufferregel 1 zou in de viewport onzichtbaar zijn')
vim.api.nvim_buf_set_lines(raw, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Nieuwe tekst.' })
wait(function() return marks(raw)[1][2] == 2 end)
vim.api.nvim_buf_delete(raw, { force = true })
vim.fn.delete(path)
print 'article virtual notices: OK'
