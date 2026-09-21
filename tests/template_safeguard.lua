-- Kopij uit een rubriektemplate hoeft niet langs de importwaarborg.
--
-- Die waarborg vergelijkt de tekst met wat er bij import binnenkwam en klaagt
-- als die nauwelijks afwijkt. Bij een raadspraat, een Kamper Kiek of een
-- eregalerij zegt dat niets: de tekst hóórt te zijn wat de auteur aanleverde.
-- Eerder gold de uitzondering alleen voor columns, omdat alleen die een
-- `rubriek: column`-regel zetten.
local ai = require 'ai_text'
local krant = require 'krant'

local function article(buf)
  local lines = {
    'e: B', '', '=== ARTIKEL ===', '',
    'Aangeleverde kop', '', 'KAMPEN - De aangeleverde tekst van de auteur.',
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  -- Doe alsof dit zo is geïmporteerd en er niets aan veranderd is.
  vim.b[buf].send_import_body = ai._editorial_body_text(lines)
  return lines
end

-- Zonder template klaagt de waarborg; dat gedrag blijft.
local plain = vim.api.nvim_create_buf(false, true)
local lines = article(plain)
local reason = ai._send_safeguard_reason(plain, lines)
assert(type(reason) == 'string' and reason:find('import', 1, true),
  'een onbewerkte import wordt niet meer tegengehouden: ' .. tostring(reason))

-- Met een toegepaste template zwijgt hij.
local templated = vim.api.nvim_create_buf(false, true)
lines = article(templated)
krant._mark_template_applied(templated, 'Eregalerij kampioenen')
assert(ai._send_safeguard_reason(templated, lines) == nil,
  'templatekopij wordt alsnog als nauwelijks bewerkt aangemerkt')

-- Een lege markering telt niet als template.
local empty = vim.api.nvim_create_buf(false, true)
lines = article(empty)
krant._mark_template_applied(empty, '')
assert(type(ai._send_safeguard_reason(empty, lines)) == 'string',
  'een lege templatenaam schakelt de waarborg uit')

-- De bestaande columnuitzondering blijft werken, ook zonder markering.
local column = vim.api.nvim_create_buf(false, true)
local column_lines = {
  'e: B', 'rubriek: column', '', '=== ARTIKEL ===', '',
  'Kop', '', 'KAMPEN - Tekst.',
}
vim.api.nvim_buf_set_lines(column, 0, -1, false, column_lines)
vim.b[column].send_import_body = ai._editorial_body_text(column_lines)
assert(ai._send_safeguard_reason(column, column_lines) == nil,
  'de columnuitzondering is verdwenen')

print 'template safeguard: OK'
