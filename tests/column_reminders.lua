local reminders = dofile(vim.fn.getcwd() .. '/plugin/column_reminders.lua')
local original_select, original_system = vim.ui.select, vim.fn.system
local captured
vim.ui.select = function(items, opts)
  captured = { items = items, opts = opts }
end
vim.fn.system = function() error('menu met opgehaalde rotatie startte nog een subprocess') end

-- Het echte Python-contract, zonder productie-status of externe calls.
local code = [[
import json, sys
from datetime import date
from pathlib import Path
from texttools.column_reminder import RAADSPRAAT, ONDERNEMEN, reminder_window, reminder_to_dict
print(json.dumps({series.slug: [reminder_to_dict(item) for item in reminder_window(
    series, today=date.fromisoformat(sys.argv[1]), status_path=Path(sys.argv[2]))]
    for series in (RAADSPRAAT, ONDERNEMEN)}))
]]
for _, day in ipairs({ '2026-10-09', '2026-10-13', '2026-10-16', '2027-01-01', '2046-09-20' }) do
  local process = vim.system({ require('texttools_commands').bin('python'), '-c', code,
    day, vim.env.TEXTTOOLS_SHARED_DIR .. '/missing-reminder-status.json' }, { text = true }):wait(5000)
  assert(process.code == 0, process.stderr)
  for series, items in pairs(vim.json.decode(process.stdout)) do
    local original = vim.json.encode(items)
    local current, current_index
    for index, item in ipairs(items) do
      if item.is_current == true then current, current_index = item, index end
    end
    assert(current, series .. ' mist actuele reminder op ' .. day)
    reminders.reminders(series, items)
    assert(current_index == 3, 'twee vorige weken ontbreken')
    assert(captured.opts.default == current_index, series .. ' selecteert niet deze week op ' .. day)
    assert(captured.opts.native, 'fuzzy picker mag beginindex/volgorde niet veranderen')
    assert(captured.opts.format_item(current):find('▶', 1, true), 'weekmarker ontbreekt')
    assert(#captured.items == #items + 1 and captured.items[#captured.items]._back,
      'andere weken of terugnavigatie verdwenen')
    for index, item in ipairs(items) do
      assert(captured.items[index] == item, 'weken zijn niet in chronologische volgorde')
    end
    assert(vim.json.encode(items) == original, 'rotatie voor planningsoverzicht is gemuteerd')
    -- De actuele week blijft geselecteerd als hij al verstuurd is.
    current.sent_at = '2026-10-09T10:00:00+02:00'
    reminders.reminders(series, items)
    assert(captured.opts.default == current_index and captured.opts.format_item(current):find('✓', 1, true),
      'verstuurstatus verschoof de selectie naar een andere week')
  end
end

local early = { { label = 'Eerste', is_current = false }, { label = 'Tweede' } }
reminders.reminders('ondernemen', early)
assert(captured.items[1] == early[1] and captured.items[2] == early[2],
  'zonder actuele week is de oorspronkelijke volgorde veranderd')
assert(captured.opts.default == 1, 'zonder actuele marker hoort de eerste week geselecteerd te zijn')

-- De echte overlay moet de opgegeven beginindex toepassen, niet alleen doorgeven.
local dialog = require('user_dialog')
dialog.setup({ manual_select = function() error('reminder opende toch de fuzzy picker') end })
local actual = {
  { label = 'Vorige week', reminder_week = 41, deadline_week = 42, publication_week = 43 },
  { label = 'Deze week', is_current = true, reminder_week = 42, deadline_week = 43, publication_week = 44 },
  { label = 'Volgende week', reminder_week = 43, deadline_week = 44, publication_week = 45 },
}
local fetch_count = 0
vim.fn.system = function(cmd)
  fetch_count = fetch_count + 1
  assert(cmd[2] == 'list' and cmd[3] == '--around-current' and cmd[4] == '--json',
    'client haalt geen chronologisch Python-venster op')
  return vim.json.encode(actual)
end
reminders.reminders('raadspraat')
assert(fetch_count == 1, 'extra CLI-call voor de menulijst')
assert(vim.wait(500, function()
  return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative ~= ''
end, 10), 'native remindervenster verscheen niet')
assert(vim.api.nvim_get_current_line():find('Deze week', 1, true), 'overlaycursor staat niet op huidige reminder')
local win = vim.api.nvim_get_current_win()
local escape = vim.fn.maparg('<Esc>', 'n', false, true)
assert(type(escape.callback) == 'function', 'handmatig remindermenu mist Escape')
escape.callback()
assert(not vim.api.nvim_win_is_valid(win), 'Escape annuleert het handmatige menu niet')
vim.ui.select, vim.fn.system = original_select, original_system
print('column reminders: OK')
