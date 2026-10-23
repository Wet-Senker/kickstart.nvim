local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local pending
require('user_dialog').select = function(items, options, done)
  pending = { items = items, options = options, done = done }
end
local native_system = vim.system
local calls, analyses = 0, 0
vim.system = function(command, options, done)
  assert(command[3] == 'texttools.calendar_preparation', 'onverwachte AI/CMS-call')
  calls = calls + 1
  return native_system(command, options, done)
end
ai._start_calendar_analysis = function(buf, explicit)
  assert(explicit and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == '---')
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(text:find('calendar_coverage:', 1, true) and text:find('Wapenveld', 1, true))
  assert(text:find('agenda: ja', 1, true) and not text:find('calendar_disabled: true', 1, true))
  analyses = analyses + 1
end
local function source()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: SW', '', '=== ARTIKEL ===', '',
    'Swolsebostocht', '', 'WAPENVELD - De tocht start om 9.00 uur.' })
  vim.b[buf].calendar_request_generation = 1
  return buf
end
local proposed = '---\ncalendar:\n  event_candidate: false\n  calendar_ready: false\n'
  .. '  excluded_cities: [Wapenveld]\n  skip_reason: outside_coverage\n'
  .. '  skip_message: "Geen agenda-item: Wapenveld valt buiten het verspreidingsgebied."\n---'
local function begin(buf)
  ai._apply_articlemeta_calendar_result(buf, { code = 0, stdout = proposed },
    vim.api.nvim_buf_get_changedtick(buf), true, nil, 1)
  assert(pending and pending.options.prompt:find('Wapenveld', 1, true))
end
local buf = source()
begin(buf)
assert(pending.items[1] == 'Geen agenda-item maken')
pending.done(pending.items[2])
assert(vim.wait(5000, function() return analyses == 1 end, 5), 'uitzondering werd niet opgeslagen/hervat')
assert(calls == 1)
-- Een wijziging tijdens het kiezen mag niet stil toestemming opslaan.
buf = source()
begin(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Een nieuwere bewerking.' })
pending.done(pending.items[2])
vim.wait(20, function() return false end)
assert(calls == 1 and analyses == 1)
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(not text:find('calendar_coverage:', 1, true) and text:find('Een nieuwere bewerking.', 1, true))
-- Annuleren doet ook geen impliciete create/toestemming.
buf = source()
begin(buf)
pending.done(nil)
assert(calls == 1 and analyses == 1)
vim.system = native_system
print 'calendar outside override: OK'
