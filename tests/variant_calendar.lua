package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
local original_system = vim.system
local original_resolver = ai._calendar_edition_resolver
local original_agenda_check = ai._check_agenda_duplicates
ai._calendar_edition_resolver = function(_buf, _text, done)
  done({ editions = { 'SW' } })
end
ai._check_agenda_duplicates = function(_buf, _codes, done) done(true) end
local callback
vim.system = dofile('tests/helpers/calendar_core.lua')(function(_, _, done)
  callback = done
  return { kill = function() end }
end)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Zwolle', '', '**ZWOLLE - Artikeltekst.**' })
vim.b[buf].edition_code = 'SW'
ai.articlemeta_calendar_buffer()
assert(vim.wait(1500, function() return callback ~= nil end), 'kalenderanalyse niet gestart')
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
assert(vim.wait(1500, function() return (vim.b[buf].pending_jobs or 0) == 0 end))
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
callback = nil
assert(vim.wait(1500, function() return callback ~= nil end))
for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line == 'Zwolle' then vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { 'Eigen nieuwe kop' }); break end
end
callback(result)
assert(vim.wait(1500, function() return (vim.b[buf].pending_jobs or 0) == 0 end))
assert(ai._editorial_body_text(vim.api.nvim_buf_get_lines(buf, 0, -1, false)):find('Eigen nieuwe kop', 1, true), 'late agenda overschreef tekst')
vim.system = original_system
ai._calendar_edition_resolver = original_resolver
ai._check_agenda_duplicates = original_agenda_check
print('variant calendar: OK')
