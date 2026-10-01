-- Een geplakte, nog niet met <leader>ka voorbereide papieren agendapagina
-- (tientallen activiteiten onder meerdere dagkoppen) is geen los artikel.
-- `agenda_page_flow`/de "=== AGENDAPAGINA ===" marker beschermen de al
-- voorbereide pagina al, maar die vlag zet <leader>ka zelf pas op het moment
-- dat de redacteur hem indrukt — BufReadPost kan de herkenning daarvóór al
-- laten afgaan, zodra het bestand na een pv-import al de ruwe, geplakte
-- tekst bevat. Dit test de puur lokale dagkoppen-telling die dat voorkomt.
local ai = require('ai_text')

local original_runner = ai._column_recognition_runner
ai._column_recognition_runner = function()
  error('artikelclassificatie had niet mogen starten voor een ruwe agendapagina')
end

local raw_agenda = table.concat({
  'donderdag 2 oktober',
  '',
  'Koffieochtend',
  '10:00 | Buurthuis',
  'Gezellig samenzijn, iedereen welkom.',
  '',
  'vrijdag 3 oktober',
  '',
  'Bingo-avond',
  '19:30 | Zalencentrum',
  'De hoofdprijs is een fruitmand.',
}, '\n')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(raw_agenda, '\n', { plain = true }))
ai._article_autodetect(buf)
assert(vim.b[buf].article_recognition_done ~= true,
  'ruwe agendapagina werd toch als los artikel herkend')

ai._column_recognition_runner = original_runner
print('agenda page raw paste skip: OK')
