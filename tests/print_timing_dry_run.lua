-- De kranttijdkeuze mag geen AI-kosten maken vóórdat de redacteur kiest.
--
-- prepare_timing_workspace genereerde altijd meteen de kranttijdsversie zodra
-- er targets waren, en bood pas dáárna de keuze (kranttijdsversie maken /
-- alleen website / annuleren). Koos de redacteur "alleen website" of
-- "annuleren", dan was die AI-generatie voor niets gedaan. temporal_print_prepare
-- vraagt nu eerst met --dry-run (geen AI) of er een versie nodig is, en
-- genereert alleen na een expliciete "kranttijdsversie maken"-keuze.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local dialog = require 'user_dialog'
local original_system, original_select, original_confirm =
  vim.system, dialog.select, dialog.confirm

local function new_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.',
  })
  return buf
end

local file = '/tmp/print-timing-dry-run-test.md'

local function run_prepare(responses, setup_buf, editions)
  local calls = {}
  local index = 0
  vim.system = function(cmd, opts, callback)
    index = index + 1
    table.insert(calls, cmd)
    local response = responses[index]
    assert(response, 'onverwachte extra subprocesaanroep #' .. index)
    vim.schedule(function() callback(response) end)
    return { kill = function() end }
  end
  local buf = new_buf()
  if setup_buf then setup_buf(buf) end
  local done_args
  ai._temporal_print_prepare(buf, file, {}, editions or { 'B' }, function(...)
    done_args = { ... }
  end)
  assert(vim.wait(2000, function() return done_args ~= nil end, 5),
    'temporal_print_prepare kwam niet tot een resultaat')
  return calls, done_args
end

local function payload(fields)
  local base = {
    contract_version = 1, markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n',
    section = vim.NIL, changed = false, requires_review = false, ai_call_count = 0,
    decision_required = false, skipped_newspaper_editions = {}, targets = {},
  }
  return vim.tbl_extend('force', base, fields or {})
end
local function ok_result(fields)
  return { code = 0, stdout = vim.json.encode(payload(fields)), stderr = '' }
end

-- 1. Geen kranttijd nodig: één dry-run aanroep, geen dialoog, direct klaar.
local calls, done_args = run_prepare({ ok_result {} })
assert(#calls == 1, 'meer dan één aanroep zonder aanleiding: ' .. #calls)
assert(vim.tbl_contains(calls[1], '--dry-run'), 'de enige aanroep was geen dry-run')
assert(done_args[1] == true and done_args[3] == false,
  'zonder aanleiding hoort er niets te wijzigen')

-- 2. Wel nodig, redacteur kiest "Alleen website": geen tweede aanroep, dus
-- geen AI-kosten gemaakt. De keuze-dialoog krijgt de dry-run-aanleiding te zien.
dialog.select = function(items, opts, done)
  error('dialog.select had niet aangeroepen mogen worden voor deze keuze')
end
dialog.confirm = function(prompt, buttons, default)
  assert(prompt:find('datumcontext', 1, true), 'verkeerde vraag getoond')
  -- De sneltoets (&) staat vóór "website", niet vóór "Alleen": anders zou
  -- deze optie dezelfde A-sneltoets claimen als Annuleren.
  assert(buttons:find('Kranttijdsversie maken', 1, true)
    and buttons:find('Alleen', 1, true) and buttons:find('website', 1, true)
    and buttons:find('Annuleren', 1, true),
    'niet alle drie de opties staan er: ' .. buttons)
  return 2 -- Alleen website
end
calls, done_args = run_prepare({ ok_result { requires_review = true, targets = { {} } } })
assert(#calls == 1, 'er werd een tweede (generatie-)aanroep gedaan ondanks "alleen website": ' .. #calls)
assert(not vim.tbl_contains(calls[1], '--allow-past-rewrite'))
assert(done_args[1] == true and done_args[3] == false,
  'alleen-website hoort requires_review niet als voltooide review te melden')
assert(type(done_args[4]) == 'table' and done_args[4][1] == 'B',
  'de editie moet als web-only worden teruggegeven')

-- 3. Wel nodig, redacteur kiest "Kranttijdsversie maken": een tweede aanroep
-- vindt plaats, nu zonder --dry-run (de echte generatie), en het resultaat
-- wordt toegepast.
dialog.confirm = function() return 1 end -- Kranttijdsversie maken
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { {} } },
  ok_result {
    requires_review = true, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
})
assert(#calls == 2, 'de bevestigde generatie vond niet plaats: ' .. #calls)
assert(vim.tbl_contains(calls[1], '--dry-run'), 'de eerste aanroep was geen dry-run')
assert(not vim.tbl_contains(calls[2], '--dry-run'),
  'de bevestigde generatie liep nog steeds als dry-run')
assert(done_args[1] == true and done_args[3] == true,
  'na echte generatie hoort requires_review/review-voltooid waar te zijn')

-- 3b. De bevestigde generatie kan terecht niets wijzigen (de AI besliste dat
-- de brontekst al klopt). Python meldt dan requires_review=false, ook al is
-- er een sectie bijgeschreven (changed=true blijft staan voor de validatie
-- bij de echte verzending). De flow mag dan niet alsnog blokkeren met
-- "controleer de vernieuwde kranttijdsversie" — er valt niets te controleren.
dialog.confirm = function() return 1 end -- Kranttijdsversie maken
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { {} } },
  ok_result {
    requires_review = false, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
})
assert(#calls == 2, 'de bevestigde generatie vond niet plaats: ' .. #calls)
assert(done_args[1] == true and done_args[3] == false,
  'een ongewijzigde bevestigde generatie hoort niet als "review nodig" te melden')

-- 4. Wel nodig, redacteur annuleert: geen tweede aanroep, geannuleerd resultaat.
dialog.confirm = function() return 0 end -- Annuleren
calls, done_args = run_prepare({ ok_result { requires_review = true, targets = { {} } } })
assert(#calls == 1, 'annuleren deed toch een tweede aanroep: ' .. #calls)
assert(done_args[1] == false, 'annuleren hoort geen succes te melden')

-- 5. Een evenement ligt al in het verleden: "Herschrijven voor krant" vraagt
-- niet nogmaals via de kranttijdskeuze-dialoog (met allow_past_rewrite=true
-- is requires_review voor zo'n target altijd waar, dus die tweede vraag zou
-- gegarandeerd hetzelfde antwoord krijgen). Eén dry-run, daarna direct de
-- bevestigde generatie — geen tussenliggende dry-run, geen tweede dialoog.
local past_confirm_calls = 0
dialog.confirm = function(prompt)
  past_confirm_calls = past_confirm_calls + 1
  assert(prompt:find('minstens één evenement', 1, true), 'verkeerde vraag getoond: ' .. prompt)
  return 1 -- Herschrijven voor krant
end
calls, done_args = run_prepare({
  ok_result { decision_required = true, targets = { {} } },
  ok_result {
    requires_review = true, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
})
assert(past_confirm_calls == 1, 'herschrijven vroeg nogmaals een bevestiging: ' .. past_confirm_calls)
assert(#calls == 2, 'herschrijven deed niet precies twee aanroepen: ' .. #calls)
assert(vim.tbl_contains(calls[1], '--dry-run'), 'de eerste aanroep was geen dry-run')
assert(not vim.tbl_contains(calls[2], '--dry-run'),
  'de tweede aanroep liep nog als dry-run i.p.v. de echte generatie')
assert(vim.tbl_contains(calls[2], '--allow-past-rewrite'), 'toestemming ontbrak in de generatie')
assert(done_args[1] == true and done_args[3] == true,
  'na herschrijven hoort de review voltooid te zijn')

-- 6. De redacteur koos bij de krantdeadline-melding al "Toch ook naar de
-- krant" voor editie B (late_newspaper_decision.mode == 'force'). Het
-- evenement in die editie ligt al in het verleden (decision_required), maar
-- omdat B zelf al expliciet is goedgekeurd voor late plaatsing, mag dat geen
-- nieuwe vraag meer opleveren: geen enkele dialoog, direct door naar de
-- bevestigde generatie.
dialog.confirm = function()
  error('geen dialoog had getoond mogen worden voor een al goedgekeurde late editie')
end
local function with_forced_late(editions)
  return function(buf)
    vim.b[buf].late_newspaper_decision = {
      signature = 'B:2026-10-01:2026-10-06:1', mode = 'force', editions = editions,
    }
  end
end
calls, done_args = run_prepare({
  ok_result {
    decision_required = true,
    targets = { { edition = 'B', transitions = { { newspaper_state = 'past' } } } },
  },
  ok_result {
    requires_review = true, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
}, with_forced_late({ 'B' }))
assert(#calls == 2, 'de automatische herschrijving deed niet precies twee aanroepen: ' .. #calls)
assert(vim.tbl_contains(calls[2], '--allow-past-rewrite'), 'toestemming ontbrak in de automatische generatie')
assert(done_args[1] == true and done_args[3] == true,
  'na automatisch herschrijven hoort de review voltooid te zijn')

-- 7. Dezelfde situatie, maar nu ligt het verleden-evenement in een editie (D)
-- die NIET in de goedgekeurde late-set zit (alleen B is goedgekeurd). Dan
-- blijft de gewone vragende flow gelden — geen stille aanname over een editie
-- waarover nog niets is beslist.
local asked = false
dialog.confirm = function()
  asked = true
  return 2 -- Niet in krant, kortste pad terug naar done()
end
calls, done_args = run_prepare({
  ok_result {
    decision_required = true,
    targets = { { edition = 'D', transitions = { { newspaper_state = 'past' } } } },
  },
  ok_result { skipped_newspaper_editions = { 'D' } },
}, with_forced_late({ 'B' }), { 'D' })
assert(asked, 'niet-goedgekeurde editie werd stilzwijgend toch doorgezet zonder te vragen')

-- 8. Geen verleden-evenement, maar wel een gewone kranttijdskeuze
-- (requires_review zonder decision_required) voor een al goedgekeurde late
-- editie: ook hier geen dialoog, direct de bevestigde generatie.
dialog.confirm = function()
  error('geen dialoog had getoond mogen worden voor een al goedgekeurde late editie')
end
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { { edition = 'B', transitions = {} } } },
  ok_result {
    requires_review = true, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
}, with_forced_late({ 'B' }))
assert(#calls == 2, 'de automatische kranttijdsgeneratie deed niet precies twee aanroepen: ' .. #calls)
assert(not vim.tbl_contains(calls[2], '--dry-run'), 'de tweede aanroep liep nog als dry-run')
assert(done_args[1] == true and done_args[3] == true,
  'na automatische generatie hoort de review voltooid te zijn')

-- 9. Een web-only editie hoort niet in de kranttijdscontrole. Live 8-10-2026:
-- na "alleen website" voor de te late editie D vroeg Neovim toch om een
-- kranttijdsversie voor D, en faalde de verzending daarna op "verwacht geen,
-- gevonden D". Alleen printedities gaan naar pubble-print-timing.
dialog.confirm = function()
  error('er mag geen kranttijdsvraag komen voor een web-only editie')
end
local function editions_of(cmd)
  for index, value in ipairs(cmd) do
    if value == '--editions' then return vim.json.decode(cmd[index + 1]) end
  end
end
local function with_late_website(editions)
  return function(buf)
    vim.b[buf].late_newspaper_decision = {
      signature = 'D:2026-10-08', mode = 'website', editions = editions,
    }
  end
end
calls, done_args = run_prepare({ ok_result {} }, with_late_website({ 'D' }), { 'K', 'B', 'D' })
assert(vim.deep_equal(editions_of(calls[1]), { 'K', 'B' }),
  'web-only editie D ging toch mee naar de kranttijdscontrole: ' .. vim.json.encode(editions_of(calls[1])))
assert(done_args[1] == true and vim.tbl_contains(done_args[4], 'D'),
  'het eindresultaat moet de web-only editie D blijven noemen')

-- 9b. Hetzelfde voor een editie die via skip_newspaper_editions web-only is.
calls, done_args = run_prepare({ ok_result {} }, function(buf)
  vim.b[buf].skip_newspaper_editions = { 'D' }
end, { 'K', 'B', 'D' })
assert(vim.deep_equal(editions_of(calls[1]), { 'K', 'B' }), 'skip-editie ging toch mee')
assert(vim.tbl_contains(done_args[4], 'D'), 'skip-editie verdween uit het eindresultaat')

-- 9c. Zonder web-only edities blijft alles ongewijzigd.
calls, done_args = run_prepare({ ok_result {} }, nil, { 'K', 'B', 'D' })
assert(vim.deep_equal(editions_of(calls[1]), { 'K', 'B', 'D' }), 'edities zijn ten onrechte gefilterd')

-- 9d. "Alleen website" raakt uitsluitend de kranttijd-targets en de edities
-- die al web-only waren; B zonder datumprobleem blijft naar de krant gaan.
dialog.confirm = function() return 2 end -- Alleen website
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { { edition = 'K', transitions = {} } } },
}, with_late_website({ 'D' }), { 'K', 'B', 'D' })
assert(#calls == 1 and done_args[1] == true, 'alleen-website deed een extra aanroep')
table.sort(done_args[4])
assert(vim.deep_equal(done_args[4], { 'D', 'K' }),
  'alleen-website mag B niet uitsluiten: ' .. vim.json.encode(done_args[4]))

-- De uitsluiting wordt boven de artikelgrens zichtbaar en blijft idempotent.
local persistent = new_buf()
local temp_file = vim.fn.tempname() .. '.md'
vim.fn.writefile(vim.api.nvim_buf_get_lines(persistent, 0, -1, false), temp_file)
assert(ai._record_newspaper_exclusions(persistent, temp_file, { 'D' }, 'evenement voorbij'),
  'uitzondering kon niet worden vastgelegd')
assert(ai._record_newspaper_exclusions(persistent, temp_file, { 'D' }, 'evenement voorbij'),
  'herhaalde uitzondering mocht niet falen')
local buffer_text = table.concat(vim.api.nvim_buf_get_lines(persistent, 0, -1, false), '\n')
local file_text = table.concat(vim.fn.readfile(temp_file), '\n')
local _, buffer_count = buffer_text:gsub('krantuitzondering: D | evenement voorbij', '')
local _, file_count = file_text:gsub('krantuitzondering: D | evenement voorbij', '')
assert(buffer_count == 1 and file_count == 1, 'herhaalde keuze schreef dubbele regels')
assert(buffer_text:find('krantuitzondering: D | evenement voorbij\n=== ARTIKEL ===', 1, true),
  'reden staat niet zichtbaar boven de artikelgrens')
vim.fn.delete(temp_file)

-- Gemengde fasen: één overzicht, één expliciete keuze, daarna uitsluitend de
-- overgebleven krant genereren. Geen vervolg-keuze voor dezelfde voorbereiding.
local mixed_questions = 0
dialog.confirm = function(prompt, buttons)
  mixed_questions = mixed_questions + 1
  assert(prompt:find('2026-10-20 t/m 2026-10-22: loopt nog', 1, true))
  assert(prompt:find('SW · krant 2026-10-28', 1, true))
  assert(buttons:find('overige herschrijven', 1, true))
  return 3
end
calls, done_args = run_prepare({
  ok_result { decision_required = true, targets = {
    { edition = 'B', newspaper_date = '2026-10-21', transitions = {
      { start = '2026-10-20', ['end'] = '2026-10-22', newspaper_state = 'ongoing' } } },
    { edition = 'SW', newspaper_date = '2026-10-28', transitions = {
      { start = '2026-10-20', ['end'] = '2026-10-22', newspaper_state = 'past' } } },
  } },
  ok_result {},
}, nil, { 'B', 'SW' })
assert(mixed_questions == 1 and #calls == 2, 'gemengde fasen vroegen dubbel')
assert(not vim.tbl_contains(calls[2], '--dry-run'), 'keuze om overige te herschrijven niet hergebruikt')
assert(vim.deep_equal(editions_of(calls[2]), { 'B' }), 'verlopen krant ging toch mee')
assert(vim.tbl_contains(done_args[4], 'SW'), 'websitekeuze ging verloren')

-- Een al goedgekeurde krant verschijnt niet opnieuw in het overzicht. Bij
-- website voor SW wordt B nog wel met de eerdere toestemming gegenereerd.
dialog.confirm = function(prompt)
  assert(prompt:find('voor SW', 1, true), 'nog niet beoordeelde editie ontbreekt')
  assert(not prompt:find('B · krant', 1, true), 'eerdere toestemming werd opnieuw gevraagd')
  return 2
end
calls, done_args = run_prepare({
  ok_result { decision_required = true, targets = {
    { edition = 'B', newspaper_date = '2026-10-28', transitions = { { newspaper_state = 'past' } } },
    { edition = 'SW', newspaper_date = '2026-10-21', transitions = { { newspaper_state = 'ongoing' } } },
  } },
  ok_result {},
}, with_forced_late({ 'B' }), { 'B', 'SW' })
assert(#calls == 2 and vim.deep_equal(editions_of(calls[2]), { 'B' }))
assert(vim.tbl_contains(calls[2], '--allow-past-rewrite'))
assert(vim.tbl_contains(done_args[4], 'SW'))

-- Webtekst behouden: de client geeft de specifieke edities door; geen
-- herschrijf-/reviewvraag na deze expliciete keuze.
local function copied_result()
  return ok_result { changed = true, ai_call_count = 0,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n' }
end
local function kept_editions(command)
  for index, part in ipairs(command) do
    if part == '--use-web-editions' then return vim.json.decode(command[index + 1]) end
  end
end
for _, past in ipairs { false, true } do
  dialog.confirm = function(_, buttons)
    assert(buttons:find('Webtekst &behouden', 1, true))
    return past and 4 or 3 -- Nieuwe zichtbare menu-index, vóór Annuleren.
  end
  calls, done_args = run_prepare({
    ok_result { decision_required = past, requires_review = not past,
      targets = { { edition = 'B', transitions = { { newspaper_state = past and 'past' or 'opening' } } } } },
    copied_result(),
  })
  assert(#calls == 2 and vim.deep_equal(kept_editions(calls[2]), { 'B' }))
  assert(not vim.tbl_contains(calls[2], '--dry-run'))
  assert(done_args[1] == true and done_args[3] == false)
end
dialog.confirm = function() error('deadlinekeuze vroeg nogmaals welke tekst') end
calls, done_args = run_prepare({
  ok_result { decision_required = true,
    targets = { { edition = 'B', transitions = { { newspaper_state = 'past' } } } } }, copied_result(),
}, function(buf)
  vim.b[buf].late_newspaper_decision = { mode = 'force', editions = { 'B' }, use_web_editions = { 'B' },
    use_web_revision = require('buffer_revision').capture(buf) }
end)
assert(#calls == 2 and vim.deep_equal(kept_editions(calls[2]), { 'B' }))
assert(done_args[1] and not done_args[3])

local asked_again = false
dialog.confirm = function() asked_again = true; return 2 end
calls, done_args = run_prepare({ ok_result { decision_required = true,
  targets = { { edition = 'B', transitions = { { newspaper_state = 'past' } } } } } }, function(buf)
  local revision = require('buffer_revision').capture(buf)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwe tekst na het behoudbesluit.' })
  vim.b[buf].late_newspaper_decision = { mode = 'force', editions = { 'B' }, use_web_editions = { 'B' },
    use_web_revision = revision }
end)
assert(asked_again and #calls == 1, 'verouderde behoudkeuze kopieerde of herschreef zonder nieuwe toestemming')

-- Inhoudelijke twijfel bewaart de aparte krantsectie en vraagt herstel, niet
-- opnieuw genereren. De webbody en controleregels blijven exact behouden.
local proposal = '## Kranttijdsversies\n\n### Kranttijdsversie B — De Brug\n\nKop\n\nKAMPEN - Voorstel met 35 punten.'
local recovery_buf
dialog.confirm = function() return 1 end
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { { edition = 'B' } } },
  ok_result {
    changed = true, requires_review = true, ai_call_count = 1,
    section = proposal,
    validation_issues = { { edition = 'B', code = 'values', message = 'Uitslag gewijzigd.',
      differences = { 'Ontbreekt of minder vaak: 36 (1×)', 'Nieuw of vaker: 35 (1×)' } } },
  },
}, function(buf) recovery_buf = buf end)
assert(#calls == 2 and done_args[1] and done_args[3])
assert(done_args[5]:find('Uitslag gewijzigd.', 1, true))
assert(done_args[5]:find('36 (1×)', 1, true) and done_args[5]:find('35 (1×)', 1, true))
local recovery_text = table.concat(vim.api.nvim_buf_get_lines(recovery_buf, 0, -1, false), '\n')
assert(recovery_text:find('KAMPEN - Tekst.', 1, true), 'webtekst overschreven door voorstel')
assert(recovery_text:find(proposal, 1, true), 'afgekeurd voorstel verloren gegaan')

-- Een bewaard maar nog niet hersteld voorstel bereikt zelfs geen keuzemenu.
dialog.confirm = function() error('afgekeurd bestaand voorstel vroeg opnieuw toestemming/AI') end
calls, done_args = run_prepare({ ok_result {
  requires_review = true, validation_issues = { { edition = 'B', message = 'Uitslag gewijzigd.' } },
} })
assert(#calls == 1 and done_args[1] and done_args[3] and done_args[5])

-- Nieuwere tekst mag ook bij een late timingrespons niet worden toegepast.
local callback
vim.system = function(_, _, cb) callback = cb; return { kill = function() end } end
local changed_buf = new_buf()
local changed_result
ai._temporal_print_prepare(changed_buf, file, {}, { 'B' }, function(...)
  changed_result = { ... }
end)
vim.api.nvim_buf_set_lines(changed_buf, -1, -1, false, { 'Nieuwere tekst.' })
callback(ok_result {})
assert(vim.wait(1000, function() return changed_result ~= nil end))
assert(changed_result[1] == false and changed_result[2]:find('Tekst gewijzigd', 1, true))

vim.system, dialog.select, dialog.confirm = original_system, original_select, original_confirm

print 'print timing dry run: OK'
