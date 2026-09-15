package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
local original_system = vim.system
local callback
vim.system = function(_, _, done)
  callback = done
  return { kill = function() end }
end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Zwolle', '', '**ZWOLLE - Artikeltekst.**' })
vim.b[buf].edition_code = 'SW'
ai.articlemeta_calendar_buffer()
assert(callback, 'kalenderanalyse niet gestart')
local result = { code = 0, stdout = [[---
calendar:
  calendar_ready: true
  event_candidate: true
  calendar_title: Open dag
  event_date: '2099-09-19'
  start_time: '10:00'
  location_name: Buurthuis
  city: Zwolle
  calendar_body: Bezoekers zijn welkom.
---
]] }
callback(result)
assert(vim.wait(500, function() return not vim.b[buf].calendar_ai_running end))
assert(ai._has_calendar_section(vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'variantagenda niet zichtbaar')
-- Source preflight must not propose an additional shared agenda.
local source = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(source, 0, -1, false, {
  'e: B, SW', '', '=== ARTIKEL ===', '', 'Bron', '', 'Evenement.',
  '', '## Editieversies', '', '### Editieversie SW', '', 'Zwolle', '',
  '#### Kalender', 'Titel: Open dag',
})
assert(ai._calendar_decision_before_send(source) == 'continue', 'lokale agenda veroorzaakte gedeelde agendavraag')
-- Late calendar results may not overwrite subsequent edits.
vim.api.nvim_set_current_buf(buf)
ai.articlemeta_calendar_buffer()
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'Eigen nieuwe kop' })
callback(result)
assert(vim.wait(500, function() return not vim.b[buf].calendar_ai_running end))
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'Eigen nieuwe kop', 'late agenda overschreef tekst')
vim.system = original_system
print('variant calendar: OK')
