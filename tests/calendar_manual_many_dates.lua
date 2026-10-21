local ai = require 'ai_text'
local original_start = ai._start_calendar_analysis
local original_confirm = ai._calendar_date_confirm
local original_check = ai._check_agenda_duplicates
local started = 0
ai._calendar_date_confirm = function() error('expliciet ac vroeg alsnog of aanmaak gewenst is') end
ai._check_agenda_duplicates = function() error('expliciet ac werd tegengehouden door automatische doublurecontrole') end
ai._start_calendar_analysis = function(_, explicit)
  assert(explicit == true)
  started = started + 1
end
for index, text in ipairs {
  'Concert op 24 augustus, 25 augustus, 26 augustus en 27 augustus.',
  'agenda: nee\n\n=== ARTIKEL ===\n\nConcert zonder datum.',
  '---\ncalendar_disabled: true\n---\n\n=== ARTIKEL ===\n\nAlleen een idee.',
} do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  vim.api.nvim_set_current_buf(buf)
  ai.articlemeta_calendar_buffer()
  assert(vim.wait(1500, function() return started == index end), 'ac startte niet')
  local output = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(output:find('## Kalender', 1, true) and output:find('agenda: ja', 1, true))
  assert(not output:find('agenda: nee', 1, true) and not output:find('calendar_disabled: true', 1, true))
end
ai._start_calendar_analysis, ai._calendar_date_confirm, ai._check_agenda_duplicates = original_start, original_confirm, original_check
print('calendar manual many dates: OK')
