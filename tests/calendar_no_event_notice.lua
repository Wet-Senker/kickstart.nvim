local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local native_system = vim.system
local reply, calls = nil, 0
vim.system = dofile('tests/helpers/calendar_core.lua')(function(command, _, done)
  assert(command[2] == '--calendar')
  calls, reply = calls + 1, done
  return { kill = function() error('kalenderanalyse werd gestopt') end }
end)
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Nieuws', '', 'Een gewoon bericht.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local empty = { code = 0, stdout = '---\ncalendar:\n  event_candidate: false\n  calendar_ready: false\n---\n' }
local function idle(buf) return (vim.b[buf].pending_jobs or 0) == 0 end
local automatic = source()
local before = text(automatic)
ai._apply_articlemeta_calendar_result(automatic, empty, vim.api.nvim_buf_get_changedtick(automatic))
assert(text(automatic) == before, 'automatisch geen evenement wijzigde de tekst')
assert(not activity.snapshot(automatic) or not next(activity.snapshot(automatic).issues))
local explicit = source()
vim.b[explicit].pubble_duplicate_gate_pending = true
ai.articlemeta_calendar_buffer()
assert(vim.wait(1500, function() return calls == 1 end), 'expliciet verzoek bleef achter automatische controle wachten')
assert(text(explicit):find('## Kalender', 1, true), 'ac liet bij gebrek aan gegevens geen invulblok zien')
reply(empty)
assert(vim.wait(1500, function() return idle(explicit) end))
assert(text(explicit):find('## Kalender', 1, true) and text(explicit):find('Datum:', 1, true))
assert(not text(explicit):find('Geen kalenderitem gedetecteerd', 1, true), 'expliciet werkblok kreeg onterechte niet-herkendmelding')
assert(text(explicit):find('ontbreken', 1, true), 'ontbrekende velden niet uitgelegd')
ai._apply_articlemeta_calendar_result(explicit, { code = 1, stderr = 'testfout' }, vim.api.nvim_buf_get_changedtick(explicit))
local state = activity.snapshot(explicit)
assert(state.entries[#state.entries].level == vim.log.levels.ERROR
  and state.entries[#state.entries].message:find('testfout', 1, true))
vim.system = native_system
print('calendar no-event notice: OK')
