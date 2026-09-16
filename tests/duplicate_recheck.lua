-- Handmatig opnieuw draaien van de doublurecontrole (<leader>ad).
local ai = require 'ai_text'

-- De actie moet als toets bestaan; een functie zonder mapping is onbereikbaar
-- voor de redacteur (ARCHITECTUURPRINCIPES principe 12). Zelfde controlewijze
-- als tests/documentation.lua: lees de registratie uit de bron.
local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')
local ai_text_source = table.concat(vim.fn.readfile(repo_root .. '/lua/ai_text.lua'), '\n')

assert(
  ai_text_source:find('vim.keymap.set("n", "<leader>ad"', 1, true),
  'geen registratie van <leader>ad in ai_text.lua'
)
assert(type(ai.recheck_duplicates) == 'function', 'recheck_duplicates ontbreekt')

-- Loopt de controle al, dan start er geen tweede en volgt alleen een melding.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.' })
vim.b[buf].pubble_duplicate_check_running = true

local started = false
local original = ai._check_duplicate_stage
ai._check_duplicate_stage = function() started = true end
ai.recheck_duplicates(buf)
ai._check_duplicate_stage = original

assert(started == false, 'er is een tweede doublurecontrole gestart')
assert(
  vim.b[buf].pubble_duplicate_check_completed == nil,
  'de gecontroleerd-markering is gewijzigd terwijl de controle al liep'
)

print 'duplicate recheck: OK'
