local wijk = require('swollenaer_wijk')
local ai = require('ai_text')

assert(ai._is_control_key('wijk'), 'wijk:-regel wordt bij herschrijven weggegooid')
assert(not wijk.needs_choice({ editions = { 'B', 'SW' } }), 'oud resolve-resultaat blijft compatibel')
assert(not wijk.needs_choice({ editions = { 'SW' }, swollenaer_wijk = nil, swollenaer_wijk_lookup = false }),
  'lege wijkregel mag geen controle starten')
assert(wijk.needs_choice({ editions = { 'SW' }, swollenaer_wijk_check = true }),
  'ontbrekende wijkregel moet de automatische controle starten')
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
local workflow_log = require('workflow_log')
local old_diagnostic = workflow_log.diagnostic
local diagnostics = {}
workflow_log.diagnostic = function(_, action, detail)
  table.insert(diagnostics, { action = action, detail = detail })
end
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
vim.api.nvim_buf_delete(buf, { force = true })

local city_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(city_buf, 0, -1, false, {
  'e: SW', '', '=== ARTIKEL ===', '', 'Kop', '', 'Stadsbreed nieuws.',
})
result = nil
wijk.ensure(city_buf, '/tmp/stadsbreed.md', {
  editions = { 'SW' }, swollenaer_wijk_check = true, swollenaer_wijk_check_mode = 'automatic',
}, function(value) result = value end)
pending({
  code = 0,
  stdout = vim.json.encode({
    status = 'citywide', suggested = 'Heel Zwolle', request_mode = 'automatic',
    diagnostics = {
      reason = 'no_location_signal', literal_area_count = 0, street_count = 0,
      cache_hits = 0, pdok_requests = 0, pdok_matches = 0, unresolved_count = 0,
      lookup_error_types = {},
    },
  }),
})
assert(vim.wait(1000, function() return result ~= nil end), 'stadsbrede controle bleef hangen')
assert(result == 'restart', 'stadsbrede standaard herstart de verzendroute niet')
lines = vim.api.nvim_buf_get_lines(city_buf, 0, -1, false)
assert(lines[3] == 'wijk: Heel Zwolle', 'stadsbrede standaard werd niet zichtbaar vastgelegd')
assert(diagnostics[#diagnostics].detail.chosen == 'Heel Zwolle', 'stadsbrede keuze ontbreekt in diagnose')
vim.api.nvim_buf_delete(city_buf, { force = true })

local suggested_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(suggested_buf, 0, -1, false, {
  'e: SW', '', '=== ARTIKEL ===', '', 'Kop', '', 'Nieuws uit Holtenbroek.',
})
local dialog = require('user_dialog')
local old_select = dialog.select
local selected_options, selected_opts, select_done
dialog.select = function(options, opts, done)
  selected_options, selected_opts, select_done = options, opts, done
end
result = nil
wijk.ensure(suggested_buf, '/tmp/holtenbroek.md', {
  editions = { 'SW' }, swollenaer_wijk_check = true, swollenaer_wijk_check_mode = 'automatic',
}, function(value) result = value end)
pending({
  code = 0,
  stdout = vim.json.encode({
    status = 'suggested', suggested = 'Holtenbroek', request_mode = 'automatic',
    evidence = { 'Wijknaam in artikel: Holtenbroek' }, streets = {},
    choices = { { name = 'Holtenbroek' }, { name = 'Heel Zwolle' }, { name = 'Berkum' } },
    diagnostics = {
      reason = 'single_candidate', literal_area_count = 1, street_count = 0,
      cache_hits = 0, pdok_requests = 0, pdok_matches = 0, unresolved_count = 0,
      lookup_error_types = {},
    },
  }),
})
assert(vim.wait(1000, function() return select_done ~= nil end), 'wijkbevestiging verscheen niet')
assert(selected_opts.required == true, 'automatische wijkvraag mag niet met Escape verdwijnen')
assert(selected_options[1] == 'Holtenbroek' and selected_options[2] == 'Heel Zwolle',
  'voorstel en stadskeuze staan niet bovenaan')
select_done('Holtenbroek')
assert(vim.wait(1000, function() return result ~= nil end), 'bevestigde wijk werd niet verwerkt')
assert(result == 'restart', 'bevestigde wijk herstart de verzendroute niet')
lines = vim.api.nvim_buf_get_lines(suggested_buf, 0, -1, false)
assert(lines[3] == 'wijk: Holtenbroek', 'bevestigde wijk werd niet zichtbaar vastgelegd')
dialog.select = old_select
vim.api.nvim_buf_delete(suggested_buf, { force = true })

workflow_log.diagnostic = old_diagnostic
vim.system = old_system

print('swollenaer wijk: OK')
