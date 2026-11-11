local ai = require 'ai_text'
-- Editieresolutie/datelines blijven echte Python-integratie. Het resultaat
-- mag niet afhangen van Pubble-I/O, AI of de snelheid van nevencontroles.
local original_agenda_candidates = ai._agenda_duplicate_candidates
local original_column_runner = ai._column_recognition_runner
local original_rubriek_runner = ai._rubriek_check_runner
ai._agenda_duplicate_candidates = function(_, _, done)
  vim.schedule(function() done({ performed = true, candidates = {} }) end)
end
ai._column_recognition_runner = function(_, _, done) done({}) end
ai._rubriek_check_runner = function(_, done) done(nil) end

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
vim.api.nvim_buf_set_lines(imported, 0, -1, false, overijssel_lines { 'e:', '',
  '=== LOG ===', '[09:09] Import opgeschoond (zonder AI).', '' })
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
assert(vim.wait(5000, function() return ai._duplicate_check_is_current(imported) end, 20),
  'multi-editie-import werd niet gecontroleerd')
assert(#duplicate_runs == 1, 'multi-editie-import moet precies één doublurecontrole starten')
assert(duplicate_runs[1].command[5] == 'B,SW,ST,K', 'verkeerde edities bij importcontrole')

local explicit = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(explicit, 0, -1, false, overijssel_lines { 'e: SW', '' })
ai._edition_autodetect(explicit, buffer_text(explicit))
assert(
  buffer_text(explicit):find('e: SW', 1, true) ~= nil and buffer_text(explicit):find('e: B, SW, ST, K', 1, true) == nil,
  'bestaande e:-regel werd bij import overschreven'
)
vim.wait(5000, function() return #duplicate_runs == 2 end, 20)
assert(#duplicate_runs == 2, 'één expliciete andere krant moet naar de doublurecontrole')
assert(duplicate_runs[2].command[5] == 'SW', 'andere krant is verkeerd doorgegeven')

local explicit_multi = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(explicit_multi, 0, -1, false, lelystad_lines { 'e: B, D', '' })
ai._edition_autodetect(explicit_multi, buffer_text(explicit_multi))
assert(
  vim.wait(5000, function() return ai._duplicate_check_is_current(explicit_multi) end, 20),
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
assert(duplicate_runs[4].command[5] == 'B', 'verouderde multi-detectie is doorgegeven')

local suggested = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(suggested, 0, -1, false, kampen_lines { 'e: B, SUGGESTIE, D', '' })
local suggestion_done = false
ai._edition_autodetect(suggested, buffer_text(suggested), function() suggestion_done = true end)
assert(vim.wait(5000, function() return suggestion_done end, 20), 'suggestiecontrole rondde niet af')
assert(#duplicate_runs == 5, 'definitieve editie is niet beoordeeld')
assert(duplicate_runs[5].command[5] == 'B', 'onbevestigde suggesties tellen als edities')

local no_dateline = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(no_dateline, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Een bericht zonder plaatsnaam', '',
  'Bewoners kunnen een vragenlijst invullen over hun leefomgeving.',
})
local default_done = false
ai._edition_autodetect(no_dateline, buffer_text(no_dateline), function() default_done = true end)
assert(vim.wait(5000, function() return default_done end, 20), 'defaulteditie rondde niet af')
assert(#duplicate_runs == 6, 'altijd-beleid krijgt artikel zonder dateline niet aangeboden')
assert(buffer_text(no_dateline):match('^e:\n'), 'onbekende editie heeft geen zichtbaar keuzevak')

local local_place = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(local_place, 0, -1, false, {
  '=== ARTIKEL ===', '',
  'Hedendaagse artiesten zingen Huub Oosterhuis', '',
  'De landelijke concertreeks doet onder meer Kampen, Apeldoorn en Amersfoort aan.',
  'Later volgen ook Dordrecht en Katwijk aan Zee.',
})
local local_place_done = false
ai._edition_autodetect(local_place, buffer_text(local_place), function()
  local_place_done = true
end)
assert(vim.wait(5000, function() return local_place_done end, 20), 'lokale plaatsdetectie rondde niet af')
local local_place_text = buffer_text(local_place)
assert(local_place_text:find('e: B\n', 1, true) == 1, 'Kampen legde editie De Brug niet vast')
assert(local_place_text:find('KAMPEN - De landelijke concertreeks', 1, true),
  'Kampen werd niet als dateline voor de intro gezet')
assert(#duplicate_runs == 7 and duplicate_runs[7].command[5] == 'B',
  'lokale plaatsdetectie gebruikte niet de vastgelegde editie')

-- Een uit Word/Pandoc afkomstige Markdown-kop met `##` is artikelinhoud, geen
-- technische staartsectie. Importherkenning moet dus gewoon de dateline lezen.
local markdown_heading = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(markdown_heading, 0, -1, false, {
  '=== ARTIKEL ===', '',
  '## Kamper ondernemers bezoeken Tuschinski tijdens jaarlijks VOC-uitje', '',
  'KAMPEN – Leden van VOC Kampen maakten hun jaarlijkse uitstapje.', '',
  'De ondernemers vertrokken per bus vanuit Kampen.',
})
local markdown_heading_done = false
ai._edition_autodetect(markdown_heading, buffer_text(markdown_heading), function()
  markdown_heading_done = true
end)
assert(vim.wait(5000, function() return markdown_heading_done end, 20),
  'import met Markdown-kop rondde editieherkenning niet af')
assert(buffer_text(markdown_heading):find('e: B\n', 1, true) == 1,
  'Markdown-kop liet de Kampen-dateline ten onrechte verdwijnen')
assert(#duplicate_runs == 8 and duplicate_runs[8].command[5] == 'B',
  'import met Markdown-kop gebruikte niet de herkende editie')

-- De normale import bevat sinds november al een leeg zichtbaar editievak.
-- Gebruik echte Python-detectie en houd alle externe checks gestubd.
local edition_resolutions = 0
local system_for_import = vim.system
vim.system = function(cmd, ...)
  if vim.tbl_contains(cmd, '--resolve-editions') then edition_resolutions = edition_resolutions + 1 end
  return system_for_import(cmd, ...)
end
for _, case in ipairs({
  { 'ZWOLLE', 'SW', 'e:' },
  { 'KAMPEN', 'B', 'editie:' },
  { 'HASSELT', 'ST', 'E:' },
  { 'STEENWIJK', 'K', 'e:' },
  { 'DRONTEN', 'D', 'e:' },
  { 'ZEEWOLDE', 'Z', 'e:' },
}) do
  local place, code, field = unpack(case)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    field, '', '=== LOG ===', '[20:03] Import opgeschoond (zonder AI).', '',
    '=== ARTIKEL ===', '', 'Vuurvogel Sinfonietta geeft concert', '',
    place .. ' – Het orkest speelt muziek van Mozart en Mendelssohn.', '',
    'Meer informatie is verkrijgbaar in ' .. place .. '.', '',
    '## Niet voor publicatie', '> Contact in Kampen.',
  })
  local before = #duplicate_runs
  local before_resolutions = edition_resolutions
  ai._article_autodetect(buf)
  assert(vim.wait(3000, function() return buffer_text(buf):find('e: ' .. code .. '\n', 1, true) == 1 end, 10),
    'de lege importregel blokkeerde de dateline ' .. place)
  assert(vim.wait(3000, function() return ai._duplicate_check_is_current(buf) end, 10))
  assert(#duplicate_runs == before + 1 and duplicate_runs[before + 1].command[5] == code,
    'de importcontrole kreeg de verkeerde editie voor ' .. place)
  assert(buffer_text(buf):find(place .. ' – Het orkest', 1, true), 'de bestaande dateline veranderde')
  assert(buffer_text(buf):find('> Contact in Kampen.', 1, true), 'redactionele noot ging verloren')
  assert(edition_resolutions == before_resolutions + 1, 'dezelfde editie is opnieuw bepaald')
end
vim.system = system_for_import

local unchosen = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(unchosen, 0, -1, false, {
  'e:', '', '=== ARTIKEL ===', '', 'Campagne voor minder afval', '',
  'Bewoners kunnen een vragenlijst invullen over hun leefomgeving.',
})
local before = #duplicate_runs
local unchosen_done = false
ai._edition_autodetect(unchosen, buffer_text(unchosen), function() unchosen_done = true end)
assert(vim.wait(3000, function() return unchosen_done end, 10))
assert(buffer_text(unchosen):find('e:\n', 1, true) == 1 and #duplicate_runs == before,
  'een onzekere import kreeg ten onrechte een editie of een doublurecontrole')

for _, field in ipairs({ 'e: SUGGESTIE, SW', 'e: DOUBLURE SW' }) do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    field, '', '=== ARTIKEL ===', '', 'Kop', '', 'ZWOLLE – Het orkest speelt.',
  })
  local done = false
  ai._edition_autodetect(buf, buffer_text(buf), function() done = true end)
  assert(vim.wait(3000, function() return done end, 10))
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == field,
    'de herkenning verving een bewaarde suggestie of doublure')
end

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
assert(vim.wait(1000, function() return calendar_starts == 2 end, 20),
  'vroeg sluiten van webcontrole blokkeerde verdere artikelbewerking')
assert(not ai._duplicate_check_is_current(rejected_calendar_event),
  'vroeg sluiten gaf onterecht publicatietoestemming')
ai._duplicate_stage_runner = normal_test_runner
ai._start_calendar_analysis = original_calendar_start

-- Een oudere import met alleen een opgeslagen editie krijgt de zichtbare
-- keuze terug; geen tweede of gegokte bestemming toevoegen.
local stored = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(stored, 0, -1, false, {
  '---', 'newspaper:', '  editions: D', '---', '', '=== LOG ===',
  '[09:09] Import opgeschoond (zonder AI).', '', '=== ARTIKEL ===', '',
  'Kop', '', 'Een bericht zonder plaatsnaam.',
})
local stored_done = false
ai._edition_autodetect(stored, buffer_text(stored), function() stored_done = true end)
assert(vim.wait(5000, function() return stored_done end, 20), 'opgeslagen editie niet afgerond')
assert(buffer_text(stored):find('e: D\n', 1, true), 'opgeslagen editie bleef onzichtbaar')

ai._duplicate_stage_runner = original_duplicate_runner
ai._agenda_duplicate_candidates = original_agenda_candidates
ai._column_recognition_runner = original_column_runner
ai._rubriek_check_runner = original_rubriek_runner

print 'edition detection: OK'
