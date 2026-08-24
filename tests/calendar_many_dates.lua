local ai = require 'ai_text'

local function many_dates_text()
  return [[
maandag 24 augustus

Concert in de kerk

20:00 uur | Buitenkerk

Bezoekers zijn welkom. Kaarten zijn verkrijgbaar en het concert begint om 20.00 uur.

dinsdag 25 augustus

Tweede activiteit

woensdag 26 augustus

Derde activiteit

donderdag 27 augustus

Vierde activiteit
]]
end

-- Meer dan drie datums mogen niet stilzwijgend kalender-AI starten. Gebruik
-- dezelfde ingebouwde confirm-route als productie, maar injecteer de keuze.
local original_confirm = ai._calendar_date_confirm
local asked_count
ai._calendar_date_confirm = function(date_count)
  asked_count = date_count
  return 2
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(many_dates_text(), '\n', { plain = true }))
local prompted = ai._calendar_autodetect(buf)
assert(prompted == true, 'kalenderdetectie rapporteerde de open vraag niet')
assert(asked_count == 4, 'bevestigingsvraag kreeg niet vier datums')
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[1] == 'agenda: nee', 'afwijzing is niet persistent in de buffer')
assert(vim.b[buf].calendar_ai_started == true, 'kalender-AI is na afwijzing niet geblokkeerd')

-- Een voorbereide papieren agendapagina wordt zonder vraag genegeerd.
asked_count = nil
local prepared = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(prepared, 0, -1, false, {
  '=== AGENDAPAGINA ===',
  '',
  '## maandag 24 augustus',
  '## dinsdag 25 augustus',
  '## woensdag 26 augustus',
  '## donderdag 27 augustus',
  'Concert begint om 20.00 uur. Bezoekers zijn welkom; kaarten verkrijgbaar.',
})
ai._calendar_autodetect(prepared)
assert(asked_count == nil, 'voorbereide papieren agendapagina kreeg toch een websitevraag')
assert(vim.b[prepared].calendar_ai_started ~= true, 'papieren agendapagina startte kalender-AI')

-- Bij een headless/embedded start zonder gekoppelde UI moet herkenning wachten
-- op UIEnter, zodat vim.ui.select niet tijdens de TUI-handshake opent.
local deferred = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(deferred, 0, -1, false, { 'Gewone tekst' })
assert(ai._schedule_article_autodetect(deferred) == 'waiting_for_ui', 'detectie wachtte niet op UIEnter')
assert(vim.b[deferred].article_recognition_done ~= true, 'detectie liep vóór UIEnter')
vim.api.nvim_exec_autocmds('UIEnter', {})
vim.wait(500, function() return vim.b[deferred].article_recognition_done == true end)
assert(vim.b[deferred].article_recognition_done == true, 'detectie liep niet na UIEnter')

ai._calendar_date_confirm = original_confirm
print 'calendar many dates: OK'
