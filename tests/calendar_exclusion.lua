-- Alleen de getypeerde kalenderwerkactie draait echt; geen AI, CMS of browser.
local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
require('user_dialog').select = function(items, options, done)
  assert(options.prompt:find('Wapenveld', 1, true))
  done(items[1])
end
local native_system = vim.system
local calls = 0
vim.system = function(command, options, done)
  assert(command[3] == 'texttools.calendar_preparation', 'onverwachte extra AI/CMS-call')
  calls = calls + 1
  return native_system(command, options, done)
end
local message = 'Geen agenda-item: Wapenveld valt buiten het verspreidingsgebied.'
local proposed = { '---', 'calendar:', '  event_candidate: false', '  calendar_ready: false',
  '  skip_reason: outside_coverage', '  skip_message: "' .. message .. '"',
  '  excluded_cities:', '  - Wapenveld', '  missing_event_fields: []', '---' }
local function source()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  local lines = { '---', 'calendar_preparation: {version: 1, state: prepared}', 'calendar:',
    '  event_candidate: true', '  calendar_ready: false', '---', '',
    'e: SW', 'agenda: ja', '@ Graag controleren.', '', '=== ARTIKEL ===', '',
    'Swolsebostocht', '', 'WAPENVELD - De tocht begint op 7 november om 9.00 uur.', '',
    '---', '', '## Kalender', '', 'Titel:', 'Datum:', 'Tijd:', 'Locatie:', 'Stad:', '',
    '## Facebook', '', 'Een eigen socialtekst.' }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].calendar_request_generation = 1
  vim.b[buf].calendar_request_source = table.concat(lines, '\n')
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function wait(test) assert(vim.wait(5000, test, 5), 'kalenderuitsluiting bleef hangen') end
local buf = source()
local notice = ai._calendar_notice(proposed)
assert(notice == message and not ai._build_calendar_section_lines(proposed))
ai._apply_articlemeta_calendar_result(buf, { code = 0, stdout = table.concat(proposed, '\n') },
  vim.api.nvim_buf_get_changedtick(buf), true, nil, 1)
wait(function() return text(buf):find('Melding: LET OP: ' .. message, 1, true) end)
assert(not text(buf):find('## Kalender', 1, true) and text(buf):find('agenda: nee', 1, true))
assert(text(buf):find('@ Graag controleren.', 1, true) and text(buf):find('Een eigen socialtekst.', 1, true))
assert(text(buf):find('WAPENVELD - De tocht begint', 1, true))
assert(not text(buf):find('ontbreken', 1, true) and not text(buf):find('Vul aan', 1, true))
assert(not vim.b[buf].cached_calendar_metadata and calls == 1)
local tick = vim.api.nvim_buf_get_changedtick(buf)
activity.record(buf, 'Detail.', nil, { detail = true })
vim.wait(30, function() return false end)
assert(vim.api.nvim_buf_get_changedtick(buf) == tick, 'melding bleef muteren')

-- Een nieuwer ingevuld blok krijgt een waarschuwing maar verdwijnt nooit.
buf = source()
local before = text(buf)
for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line == 'Titel:' then
    vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { 'Titel: Mijn eigen kalenderbericht' })
    break
  end
end
local newer = text(buf)
assert(newer ~= before)
ai._apply_articlemeta_calendar_result(buf, { code = 0, stdout = table.concat(proposed, '\n') },
  vim.api.nvim_buf_get_changedtick(buf), true, nil, 1)
wait(function() return text(buf):find('Het bestaande kalenderblok is behouden.', 1, true) end)
assert(text(buf):find('Titel: Mijn eigen kalenderbericht', 1, true))
assert(text(buf):find('agenda: ja', 1, true))
assert(calls == 2)
vim.system = native_system
print 'calendar exclusion: OK'
