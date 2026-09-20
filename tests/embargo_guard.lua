local ai = require 'ai_text'

local blocker = 'EMBARGO: NIET VERSTUREN — VERWIJDER DEZE REGEL PAS NA VRIJGAVE'
local signal = {
  detected = true,
  control_line = blocker,
  source_text = '**Let op: onder embargo tot 19 september, 11.30 uur**',
  suggested_publication_at = '2026-09-19 11:30',
  message = 'Embargo gevonden. Verzending is geblokkeerd.',
}

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'Persbericht onder embargo',
  '',
  'KAMPEN - Tekst.',
})

local inserted, message = ai._apply_import_embargo(buf, signal)
assert(inserted == true, 'embargoblokkade werd bij import niet toegevoegd')
assert(message == signal.message, 'embargomelding ging verloren')
assert(vim.b[buf].embargo_import_detected == true, 'bufferstatus ontbreekt')

local result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(
  result:find(blocker, 1, true) ~= nil
    and result:find('publicatiedatum: 2026-09-19 11:30', 1, true) ~= nil
    and result:find('embargobron: **Let op: onder embargo tot 19 september, 11.30 uur**', 1, true) ~= nil,
  'embargogegevens staan niet volledig in het beschermde blok'
)
assert(
  ai._embargo_publication_suggestion(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    == '2026-09-19T11:30',
  'voorgesteld embargomoment is niet leesbaar voor de planning'
)

local inserted_again = ai._apply_import_embargo(buf, signal)
assert(inserted_again == false, 'de eerste-importblokkade werd dubbel toegevoegd')
result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
local _, count = result:gsub('EMBARGO:', '')
assert(count == 1, 'embargoregel staat meer dan één keer in de buffer')
local _, source_count = result:gsub('embargobron:', '')
assert(source_count == 1, 'letterlijke embargobron staat meer dan één keer in de buffer')
local _, date_count = result:gsub('publicatiedatum:', '')
assert(date_count == 1, 'voorgestelde publicatiedatum staat meer dan één keer in de buffer')

local clean = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(clean, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Gewoon artikel', '', 'Tekst.',
})
assert(
  ai._apply_import_embargo(clean, { detected = false }) == false,
  'een import zonder embargo kreeg toch een blokkade'
)

print('embargo guard: OK')
