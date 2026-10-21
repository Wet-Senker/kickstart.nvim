-- Routering en uitstelgedrag met de echte adapters, zonder AI/CMS-verkeer.
local activity = require 'article_activity'
local notify = require 'texttools_notify'
local dialog = require 'user_dialog'
local config = table.concat(vim.fn.readfile('init.lua'), '\n')
assert(not config:find('activity_ui.statusline(buf)', 1, true), 'losse aandachtsmelding bleef in statusbalk')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
dialog.setup()
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
local body = require('ai_text')._editorial_body_text(vim.api.nvim_buf_get_lines(source, 0, -1, false))
local function panel()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == 'texttools_activity' then return win end
  end
end
local function wait(test) assert(vim.wait(1000, test, 5)) end
local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(map.callback) == 'function', 'toets ontbreekt: ' .. lhs)
  map.callback()
end
vim.wait(30, function() return false end)
assert(not panel(), 'logboek opende zonder verzoek')
local function notices()
  local found = {}
  for _, line in ipairs(vim.api.nvim_buf_get_lines(source, 0, -1, false)) do
    if line:match('^Melding:') then found[#found + 1] = line end
  end
  return found
end
notify.workflow('Controleer de foto.', vim.log.levels.WARN, { buf = source })
wait(function() return #notices() == 1 end)
assert(not panel(), 'waarschuwing opende het logboek')
assert(vim.api.nvim_get_current_buf() == source, 'waarschuwing nam focus over')
notify.notify('Vul de ontbrekende tijd in.', nil, { buf = source, attention = true })
wait(function() return vim.inspect(notices()):find('Vul de ontbrekende tijd', 1, true) end)
assert(activity.snapshot(source).attention.message == 'Controleer de foto.', 'instructie verdrong zwaardere waarschuwing')

local answered, answer = 0, nil
dialog.select({ 'Ja', 'Nee' }, { prompt = 'Kies bestemming', source_buf = source, required = true, default = 2 }, function(value)
  answered, answer = answered + 1, value
end)
wait(function() return vim.api.nvim_win_get_config(0).relative == 'editor' end)
key('<Esc>')
assert(answered == 0, 'uitstellen koos impliciet een antwoord')
activity.clear_instruction(source)
local question
for _, issue in pairs(activity.snapshot(source).issues) do
  if issue.kind == 'question' then question = issue end
end
assert(question, 'andere actie wiste een onbeantwoorde vraag')
vim.cmd 'TexttoolsVraag'
wait(function() return vim.api.nvim_win_get_config(0).relative == 'editor' end)
key('<CR>')
assert(answered == 1 and answer == 'Nee', 'hervatten verloor de expliciete selectie')
for _, issue in pairs(activity.snapshot(source).issues) do assert(issue.kind ~= 'question', 'beantwoorde vraag bleef actueel') end

-- Test de interactieve confirm-adapter ook headless met een echt overlay.
local original_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function() return { {} } end
local choice
dialog.confirm_async('Doorgaan?', '&Ja\n&Annuleren', 2, false, function(value) choice = value end, { source_buf = source })
assert(choice == nil, 'confirm_async blokkeerde of antwoordde vóór invoer')
wait(function() return vim.api.nvim_win_get_config(0).relative == 'editor' end)
assert(vim.wo.winblend == 0, 'keuzevenster is transparant')
key('<Esc>')
assert(choice == 0, 'Escape gaf toestemming')
vim.api.nvim_list_uis = original_uis
assert(require('ai_text')._editorial_body_text(vim.api.nvim_buf_get_lines(source, 0, -1, false)) == body,
  'meldingen wijzigden de artikelbody')

-- Nieuwe Texttools-resultaten mogen de centrale router niet omzeilen.
for _, path in ipairs(vim.fn.glob('lua/*.lua', false, true)) do
  if path ~= 'lua/texttools_notify.lua' then
    local content = table.concat(vim.fn.readfile(path), '\n')
    assert(not content:find('vim.notify(', 1, true), 'rechtstreekse resultaatmelding in ' .. path)
  end
end
print 'notification policy: OK'
