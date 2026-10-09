package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require 'ai_text'

local buf = vim.api.nvim_create_buf(false, true)
local first = ai._begin_publication_planning(buf)
assert(type(first) == 'number', 'eerste publicatieplanning kreeg geen token')
assert(ai._begin_publication_planning(buf) == nil,
  'een tweede publicatieplanning kon naast de eerste starten')

assert(not ai._finish_publication_planning(buf, first + 1),
  'een late of vreemde callback gaf de actieve planning vrij')
assert(ai._begin_publication_planning(buf) == nil,
  'een fout token verwijderde de actieve planningspoort')
assert(ai._finish_publication_planning(buf, first),
  'de eigenaar kon de planningspoort niet vrijgeven')

local second = ai._begin_publication_planning(buf)
assert(type(second) == 'number' and second > first,
  'een nieuwe planning kreeg geen nieuw generatie-token')
assert(ai._finish_publication_planning(buf, second),
  'de tweede planning kon niet worden afgerond')

-- Integratie: herhaald <leader>aw stopt vóór ieder subprocess zolang de
-- datumkiezer openstaat. De bestaande vraag blijft daarmee de enige flow die
-- later een publicatie kan starten.
local guarded = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(guarded, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.',
})
local token = ai._begin_publication_planning(guarded)
local original_system = vim.system
local system_calls = 0
vim.system = function()
  system_calls = system_calls + 1
  error 'subprocess gestart ondanks openstaande publicatieplanning'
end
local ok, err = pcall(ai.pubble_send, guarded)
vim.system = original_system
assert(ok, err)
assert(system_calls == 0, 'herhaalde verzending startte opnieuw extern werk')
assert(ai._finish_publication_planning(guarded, token),
  'test kon de openstaande planningspoort niet opruimen')

print 'publication planning guard: OK'
