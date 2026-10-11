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
from texttools.column_reminder import RAADSPRAAT, ONDERNEMEN, current_rotation, reminder_to_dict
print(json.dumps({series.slug: [reminder_to_dict(item) for item in current_rotation(
    series, today=date.fromisoformat(sys.argv[1]), status_path=Path(sys.argv[2]))]
    for series in (RAADSPRAAT, ONDERNEMEN)}))
]]
for _, day in ipairs({ '2026-10-09', '2026-10-16', '2027-01-01', '2046-09-20' }) do
  local process = vim.system({ require('texttools_commands').bin('python'), '-c', code,
    day, vim.env.TEXTTOOLS_SHARED_DIR .. '/missing-reminder-status.json' }, { text = true }):wait(5000)
  assert(process.code == 0, process.stderr)
  for series, items in pairs(vim.json.decode(process.stdout)) do
    local original = vim.json.encode(items)
    local current
    for _, item in ipairs(items) do
      if item.is_current == true then current = item end
    end
    assert(current, series .. ' mist actuele reminder op ' .. day)
    reminders.reminders(series, items)
    assert(captured.items[1] == current, series .. ' selecteert niet deze week op ' .. day)
    assert(captured.opts.default == 1, 'native menu mist de actuele standaardkeuze')
    assert(captured.opts.format_item(captured.items[1]):find('▶', 1, true), 'weekmarker ontbreekt')
    assert(#captured.items == #items + 1 and captured.items[#captured.items]._back,
      'andere weken of terugnavigatie verdwenen')
    local index = 2
    for _, item in ipairs(items) do
      if item ~= current then
        assert(captured.items[index] == item, 'overige weken zijn niet in oorspronkelijke volgorde')
        index = index + 1
      end
    end
    assert(vim.json.encode(items) == original, 'rotatie voor planningsoverzicht is gemuteerd')
    -- De actuele week blijft geselecteerd als hij al verstuurd is.
    current.sent_at = '2026-10-09T10:00:00+02:00'
    reminders.reminders(series, items)
    assert(captured.items[1] == current and captured.opts.format_item(current):find('✓', 1, true),
      'verstuurstatus verschoof de selectie naar een andere week')
  end
end

local early = { { label = 'Eerste', is_current = false }, { label = 'Tweede' } }
reminders.reminders('ondernemen', early)
assert(captured.items[1] == early[1] and captured.items[2] == early[2],
  'zonder actuele week is de oorspronkelijke volgorde veranderd')
vim.ui.select, vim.fn.system = original_select, original_system
print('column reminders: OK')
