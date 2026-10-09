local wijk = require('swollenaer_wijk')
local ai = require('ai_text')

assert(ai._is_control_key('wijk'), 'wijk:-regel wordt bij herschrijven weggegooid')
assert(not wijk.needs_choice({ editions = { 'B', 'SW' } }), 'ontbrekende wijk is stadsbreed')
assert(not wijk.needs_choice({ editions = { 'SW' }, swollenaer_wijk = nil, swollenaer_wijk_lookup = false }),
  'lege wijkregel mag geen controle starten')
assert(wijk.needs_choice({ editions = { 'B', 'SW' }, swollenaer_wijk_lookup = true }),
  'wijk: auto moet de straatcontrole starten')
assert(not wijk.needs_choice({ editions = { 'B' } }), 'andere krant vraagt om wijk')
assert(not wijk.needs_choice({ editions = { 'SW' }, swollenaer_wijk = 'Heel Zwolle' }),
  'stadsbrede keuze is al vastgelegd')

local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '---', 'web:', '  draft: false', '---', '', 'e: SW', '',
  '=== ARTIKEL ===', '', 'Kop', '', 'Nieuws uit Zwolle.',
})
assert(wijk.set_control(buf, 'Berkum'), 'wijk niet zichtbaar toegevoegd')
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[8] == 'wijk: Berkum' and lines[9] == '=== ARTIKEL ===',
  'wijkregel staat niet direct boven de artikelgrens')
assert(wijk.set_control(buf, 'Heel Zwolle'), 'wijk niet te wijzigen')
lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[8] == 'wijk: Heel Zwolle', 'bestaande wijkregel niet vervangen')

local old_system = vim.system
local pending
vim.system = function(_, _, callback)
  pending = callback
  return {}
end
local result
wijk.ensure(buf, '/tmp/voorbeeld.md', { editions = { 'SW' }, swollenaer_wijk_lookup = true }, function(value)
  result = value
end)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Intussen gewijzigd.' })
pending({ code = 0, stdout = vim.json.encode({ status = 'suggested', suggested = 'Berkum' }) })
assert(vim.wait(1000, function() return result ~= nil end), 'asynchrone wijkcontrole bleef hangen')
assert(result:find('gewijzigd', 1, true), 'oude wijkanalyse overschreef nieuwere tekst')
vim.system = old_system
vim.api.nvim_buf_delete(buf, { force = true })

print('swollenaer wijk: OK')
