local ai = require 'ai_text'

local blocker = 'EMBARGO: NIET VERSTUREN — VERWIJDER DEZE REGEL PAS NA VRIJGAVE'
local signal = {
  detected = true,
  control_line = blocker,
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
  result:find(blocker .. '\ne: B\n\n=== ARTIKEL ===', 1, true) == 1,
  'embargoregel staat niet in het beschermde blok boven de artikelgrens'
)

local inserted_again = ai._apply_import_embargo(buf, signal)
assert(inserted_again == false, 'de eerste-importblokkade werd dubbel toegevoegd')
result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
local _, count = result:gsub('EMBARGO:', '')
assert(count == 1, 'embargoregel staat meer dan één keer in de buffer')

local clean = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(clean, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Gewoon artikel', '', 'Tekst.',
})
assert(
  ai._apply_import_embargo(clean, { detected = false }) == false,
  'een import zonder embargo kreeg toch een blokkade'
)

print('embargo guard: OK')
