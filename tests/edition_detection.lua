local ai = require 'ai_text'

local original_duplicate_runner = ai._duplicate_stage_runner
local duplicate_runs = {}
ai._duplicate_stage_runner = function(command, callback, options)
  table.insert(duplicate_runs, { command = command, options = options })
  callback(true, { performed = true, candidates = {}, article_fingerprint = 'test' })
end

local function buffer_text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

local function overijssel_lines(prefix)
  local lines = prefix or {}
  table.insert(lines, '=== ARTIKEL ===')
  table.insert(lines, '')
  table.insert(lines, 'Overijsselse campagne tegen zorgcriminaliteit')
  table.insert(lines, '')
  table.insert(lines, 'Inwoners van Overijssel leren signalen herkennen.')
  table.insert(lines, 'De provincie Overijssel ondersteunt de campagne.')
  return lines
end

local function kampen_lines(prefix)
  local lines = prefix or {}
  table.insert(lines, '=== ARTIKEL ===')
  table.insert(lines, '')
  table.insert(lines, 'Campagne tegen zorgcriminaliteit')
  table.insert(lines, '')
  table.insert(lines, 'KAMPEN - Inwoners leren signalen herkennen.')
  return lines
end

local function lelystad_lines(prefix)
  local lines = prefix or {}
  table.insert(lines, '=== ARTIKEL ===')
  table.insert(lines, '')
  table.insert(lines, 'Batavia gaat aan land')
  table.insert(lines, '')
  table.insert(lines, 'LELYSTAD - De Batavia wordt naar Amsterdam gesleept.')
  return lines
end

local imported = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(imported, 0, -1, false, overijssel_lines())
ai._edition_autodetect(imported, buffer_text(imported))
assert(
  vim.wait(5000, function() return buffer_text(imported):find('e: B, SW, ST, K', 1, true) ~= nil end, 20),
  'provinciebrede bestemming werd bij import niet ingevuld'
)
assert(
  vim.wait(5000, function() return buffer_text(imported):find('OVERIJSSEL - Inwoners', 1, true) ~= nil end, 20),
  'provinciale dateline werd bij import niet toegevoegd'
)
assert(vim.b[imported].edition_recognition_done == true, 'eenmalige importmarkering ontbreekt')
assert(vim.b[imported].pubble_duplicate_check_completed == true, 'multi-editie-import werd niet gecontroleerd')
assert(#duplicate_runs == 1, 'multi-editie-import moet precies één doublurecontrole starten')
assert(duplicate_runs[1].command[#duplicate_runs[1].command] == 'B,SW,ST,K', 'verkeerde edities bij importcontrole')

local explicit = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(explicit, 0, -1, false, overijssel_lines { 'e: SW', '' })
ai._edition_autodetect(explicit, buffer_text(explicit))
assert(
  buffer_text(explicit):find('e: SW', 1, true) ~= nil and buffer_text(explicit):find('e: B, SW, ST, K', 1, true) == nil,
  'bestaande e:-regel werd bij import overschreven'
)
vim.wait(5000, function() return #duplicate_runs == 2 end, 20)
assert(#duplicate_runs == 2, 'één expliciete andere krant moet naar de doublurecontrole')
assert(duplicate_runs[2].command[#duplicate_runs[2].command] == 'SW', 'andere krant is verkeerd doorgegeven')

local explicit_multi = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(explicit_multi, 0, -1, false, lelystad_lines { 'e: B, D', '' })
ai._edition_autodetect(explicit_multi, buffer_text(explicit_multi))
assert(
  vim.wait(5000, function() return vim.b[explicit_multi].pubble_duplicate_check_completed == true end, 20),
  'expliciete multi-editie-import werd niet gecontroleerd'
)
assert(#duplicate_runs == 3, 'expliciete multi-editie-import startte geen enkele controle')

local second_done = false
ai._check_duplicate_stage(explicit_multi, { 'B', 'D' }, 'herschrijven', function(ok)
  second_done = ok
end)
assert(second_done == true, 'reeds afgeronde controle blokkeerde vervolgflow')
assert(#duplicate_runs == 3, 'dezelfde buffer werd ten onrechte opnieuw gecontroleerd')

local changed_while_resolving = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(changed_while_resolving, 0, -1, false, overijssel_lines())
local race_done = false
ai._edition_autodetect(changed_while_resolving, buffer_text(changed_while_resolving), function()
  race_done = true
end)
vim.api.nvim_buf_set_lines(changed_while_resolving, 0, 0, false, { 'e: B', '' })
assert(vim.wait(5000, function() return race_done end, 20), 'gewijzigde e:-keuze rondde niet af')
-- De late keuze B blijft de gekozen editie. Plaatsvermeldingen uit andere
-- gebieden mogen er als `SUGGESTIE, …` achter komen, maar de verouderde
-- multi-detectie mag B nooit als bestemming overschrijven (`e: B, SW, ST, K`).
assert(
  buffer_text(changed_while_resolving):match('e: B[,\n]')
    and buffer_text(changed_while_resolving):find('e: B, SW, ST, K', 1, true) == nil,
  'late resolutie overschreef eigen keuze'
)
assert(#duplicate_runs == 4, 'actuele editie ging niet naar het gedeelde beleid')
assert(duplicate_runs[4].command[#duplicate_runs[4].command] == 'B', 'verouderde multi-detectie is doorgegeven')

local suggested = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(suggested, 0, -1, false, kampen_lines { 'e: B, SUGGESTIE, D', '' })
local suggestion_done = false
ai._edition_autodetect(suggested, buffer_text(suggested), function() suggestion_done = true end)
assert(vim.wait(5000, function() return suggestion_done end, 20), 'suggestiecontrole rondde niet af')
assert(#duplicate_runs == 5, 'definitieve editie is niet beoordeeld')
assert(duplicate_runs[5].command[#duplicate_runs[5].command] == 'B', 'onbevestigde suggesties tellen als edities')

local no_dateline = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(no_dateline, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Een bericht zonder plaatsnaam', '',
  'Bewoners kunnen een vragenlijst invullen over hun leefomgeving.',
})
local default_done = false
ai._edition_autodetect(no_dateline, buffer_text(no_dateline), function() default_done = true end)
assert(vim.wait(5000, function() return default_done end, 20), 'defaulteditie rondde niet af')
assert(#duplicate_runs == 6, 'altijd-beleid krijgt artikel zonder dateline niet aangeboden')

local empty = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(empty, 0, -1, false, { '=== ARTIKEL ===', '' })
local original_system = vim.system
vim.system = function() error('blanco import startte een subprocess') end
ai._article_autodetect(empty)
ai._edition_autodetect(empty, buffer_text(empty))
vim.system = original_system
assert(not vim.b[empty].article_recognition_done and not vim.b[empty].edition_recognition_done,
  'blanco import is te vroeg als herkend gemarkeerd')

local original_confirm = ai._edition_rewrite_confirm
local kept = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(kept, 0, -1, false, lelystad_lines { 'e: br, dr', '' })
local asked
ai._edition_rewrite_confirm = function(current_label, detected_label, source)
  asked = { current_label, detected_label, source }
  return 1
end
local keep_done = false
ai._reconcile_editions_after_rewrite(
  kept,
  buffer_text(kept),
  buffer_text(kept),
  function(ok) keep_done = ok end
)
assert(vim.wait(5000, function() return keep_done end, 20), 'rewritecontrole rondde niet af')
assert(asked == nil, 'ongewijzigde inhoudsdetectie vroeg toch om een keuze')
assert(buffer_text(kept):find('e: br, dr', 1, true), 'bewust ruimere e:-keuze werd niet behouden')

local changed = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(changed, 0, -1, false, overijssel_lines { 'e: SW', '' })
ai._edition_rewrite_confirm = function() return 2 end
local change_done = false
ai._reconcile_editions_after_rewrite(
  changed,
  buffer_text(changed),
  table.concat(kampen_lines { 'e: SW', '' }, '\n'),
  function(ok) change_done = ok end
)
assert(vim.wait(5000, function() return change_done end, 20), 'rewritewijziging rondde niet af')
assert(buffer_text(changed):find('e: B, SW, ST, K', 1, true), 'bevestigde nieuwe bestemming werd niet vastgelegd')
ai._edition_rewrite_confirm = original_confirm

-- Zonder betrouwbare detectie (stille De-Brug-default) blijft bevestigen verplicht.
local standaard = {
  has_explicit_editions = false,
  detection = { confidence = 'none', editions = {} },
}
assert(ai._needs_edition_send_confirmation(standaard), 'stille De-Brug-default vraagt geen bevestiging')
assert(ai._edition_send_autorecord(standaard) == nil, 'default zonder detectie wordt onterecht vastgelegd')

-- Een dateline is gezaghebbend: die legt zichzelf vast zonder tussenvraag.
local dateline = {
  has_explicit_editions = false,
  detection = {
    confidence = 'high',
    editions = { 'B' },
    names = { 'De Brug' },
    source = 'dateline KAMPEN',
  },
}
assert(not ai._needs_edition_send_confirmation(dateline), 'betrouwbare dateline vraagt onnodig bevestiging')
local recorded = ai._edition_send_autorecord(dateline)
assert(recorded and recorded.editions[1] == 'B', 'dateline wordt niet als bestemming vastgelegd')

assert(not ai._needs_edition_send_confirmation { has_explicit_editions = true }, 'expliciete aw-bestemming vraagt onnodig bevestiging')

-- Importkalender-AI mag pas starten nadat een mogelijke doublure is
-- beoordeeld. De zoekactie zelf blijft asynchroon; alleen de AI-start wacht.
local normal_test_runner = ai._duplicate_stage_runner
local original_calendar_start = ai._start_calendar_analysis
local held_duplicate_callback
local calendar_starts = 0
ai._duplicate_stage_runner = function(_, callback)
  held_duplicate_callback = callback
end
ai._start_calendar_analysis = function(target)
  assert(vim.api.nvim_buf_is_valid(target), 'kalender kreeg een ongeldige buffer')
  calendar_starts = calendar_starts + 1
end
local calendar_event = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(calendar_event, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '',
  'Jubileumconcert in de Bovenkerk', '',
  'KAMPEN - CRK Voices geeft zaterdag 19 september 2026 om 20.00 uur een concert.',
  'Bezoekers zijn welkom en kaarten zijn verkrijgbaar.',
})
ai._article_autodetect(calendar_event)
assert(
  vim.wait(5000, function() return held_duplicate_callback ~= nil end, 20),
  'import bereikte de doublurecontrole niet'
)
assert(calendar_starts == 0, 'kalender-AI startte vóór het doublurebesluit')
held_duplicate_callback(true, {
  performed = true,
  candidates = { { headline = 'Mogelijke bestaande versie' } },
})
assert(
  vim.wait(1000, function() return calendar_starts == 1 end, 20),
  'kalender-AI startte niet na het doublurebesluit'
)

held_duplicate_callback = nil
local rejected_calendar_event = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(rejected_calendar_event, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '',
  'Tweede jubileumconcert in de Bovenkerk', '',
  'KAMPEN - Het concert begint zondag 20 september 2026 om 15.00 uur.',
  'Bezoekers zijn welkom en kaarten zijn verkrijgbaar.',
})
ai._article_autodetect(rejected_calendar_event)
assert(
  vim.wait(5000, function() return held_duplicate_callback ~= nil end, 20),
  'afwijsbaar importartikel bereikte de doublurecontrole niet'
)
held_duplicate_callback(false, {
  performed = true,
  candidates = { { headline = 'Bestaande versie' } },
})
vim.wait(100, function() return calendar_starts > 1 end, 20)
assert(calendar_starts == 1, 'afgewezen doublure startte alsnog kalender-AI')
ai._duplicate_stage_runner = normal_test_runner
ai._start_calendar_analysis = original_calendar_start

ai._duplicate_stage_runner = original_duplicate_runner

print 'edition detection: OK'
