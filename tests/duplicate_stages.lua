local ai = require 'ai_text'
-- Deze test controleert de artikel-doublurepoort, niet de onafhankelijke
-- editie-/agenda-I/O die een handmatige kalenderactie eveneens start.
local original_calendar_resolver = ai._calendar_edition_resolver
local original_agenda_candidates = ai._agenda_duplicate_candidates
local calendar_resolutions, agenda_checks = 0, 0
ai._calendar_edition_resolver = function(_, _, done)
  calendar_resolutions = calendar_resolutions + 1
  vim.schedule(function() done({ editions = { 'B', 'D' } }) end)
end
ai._agenda_duplicate_candidates = function(_, _, done)
  agenda_checks = agenda_checks + 1
  vim.schedule(function() done({ performed = true, candidates = {} }) end)
end
local original_system = vim.system
vim.system = function() error('doubluretest startte onverwacht een echt subprocess') end
local original_runner = ai._duplicate_stage_runner
local runs, pending, temporary, options, last_command = 0, nil, nil, nil, nil
ai._duplicate_stage_runner = function(command, callback, opts)
  runs, pending, temporary, options, last_command = runs + 1, callback, command[2], opts, command
  assert(command[3] == '--json' and command[4] == '--editions', 'actiecontract ontbreekt')
end
local function command_has_pair(command, flag, value)
  for index, item in ipairs(command or {}) do
    if item == flag and command[index + 1] == value then return true end
  end
  return false
end
local function buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B, D', '', '=== ARTIKEL ===', '', 'Batavia aan land', '',
    'LELYSTAD - Het schip krijgt groot onderhoud.',
  })
  return buf
end
local function settled(buf)
  assert(vim.wait(1000, function()
    return (vim.b[buf].pending_jobs or 0) == 0
      and vim.b[buf].manual_calendar_duplicate_pending ~= true
  end), 'pending_jobs of handmatige agendacontrole bleef hangen')
end
local success = { version = 1, performed = true, candidates = {} }
local buf = buffer()
local approved
ai._check_duplicate_stage(buf, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
assert(runs == 1 and vim.b[buf].pending_jobs == 1, 'vroege controle ontbreekt in jobregistratie')
assert(options.approve_label == 'doorgaan met bewerken', 'import stelt verzenden voor')
assert(vim.fn.filereadable(temporary) == 1, 'tijdelijk artikel ontbreekt')
ai._check_duplicate_stage(buf, { 'B', 'D' }, 'herschrijven', function(ok) assert(not ok) end)
assert(runs == 1, 'tweede controle gestart terwijl eerste nog draait')
pending(true, nil) -- netwerkfout, gebruiker gaat door
settled(buf)
assert(approved and not ai._duplicate_check_is_current(buf), 'fout is ten onrechte afgerond')
assert(vim.fn.filereadable(temporary) == 0, 'tijdelijk artikel achtergelaten')

ai._check_duplicate_stage(buf, { 'B', 'D' }, 'herschrijven', function(ok) approved = ok end)
assert(runs == 2, 'herschrijven pakt mislukte importcontrole niet op')
pending(true, success)
settled(buf)
ai._check_duplicate_stage(buf, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
assert(approved and runs == 2, 'send herhaalt een afgeronde controle')

local fallback = buffer()
ai._check_duplicate_stage(fallback, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
assert(runs == 3 and options.approve_label == 'toch verzenden', 'send-vangnet ontbreekt')
pending(true, success)
settled(fallback)
assert(approved and ai._duplicate_check_is_current(fallback), 'send-vangnet faalde')

local stale = buffer()
ai._check_duplicate_stage(stale, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.api.nvim_buf_set_lines(stale, -1, -1, false, { 'Nieuwe inhoud tijdens de vergelijking.' })
vim.b[stale].send_requested = true
assert(options.is_current(), 'tekstwijziging brak een alleen-lezen controle af')
pending(true, success)
settled(stale)
assert(approved and not ai._duplicate_check_is_current(stale), 'bewerken werd geblokkeerd of nieuwe tekst gold ten onrechte als gecontroleerd')
assert(vim.b[stale].pubble_duplicate_editing_review, 'bewerkingsovergang ontbreekt na gewijzigde bron')
assert(not vim.b[stale].send_requested, 'wijziging tijdens lezen startte onbedoeld een uitgestelde verzending')

local sections = buffer()
ai._check_duplicate_stage(sections, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.api.nvim_buf_set_lines(sections, -1, -1, false, { '', '---', '', '## Facebook', '', 'Socialtekst' })
assert(options.is_current(), 'parallelle socialtekst maakt artikelcontrole onnodig ongeldig')
pending(true, success)
settled(sections)
assert(approved, 'parallelle socialtekst blokkeert afronden')

local cancelled = buffer()
ai._check_duplicate_stage(cancelled, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
pending(false, success)
settled(cancelled)
assert(approved and not ai._duplicate_check_is_current(cancelled), 'sluiten blokkeerde bewerken of gold als publicatietoestemming')

-- Automatische kalenderverzoeken blijven achter de webcontrole wachten;
-- expliciet ac heeft zijn eigen contracttest en wordt niet meer tegengehouden.
local original_resume = ai._resume_deferred_calendar
local resumed = 0
ai._resume_deferred_calendar = function() resumed = resumed + 1 end
local waiting_calendar = buffer()
ai._check_duplicate_stage(waiting_calendar, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.b[waiting_calendar].calendar_ai_waiting_for_duplicate = true
pending(true, success)
settled(waiting_calendar)
assert(resumed == 1, 'automatische kalenderanalyse werd niet na de webcontrole hervat')
local abandoned_calendar = buffer()
ai._check_duplicate_stage(abandoned_calendar, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
pending(false, success)
settled(abandoned_calendar)
assert(approved and not ai._duplicate_check_is_current(abandoned_calendar),
  'sluiten blokkeerde bewerken of werd als publicatietoestemming onthouden')
ai._resume_deferred_calendar = original_resume

local removed = buffer()
ai._check_duplicate_stage(removed, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
vim.api.nvim_buf_delete(removed, { force = true })
pending(true, success)
assert(not approved and vim.fn.filereadable(temporary) == 0, 'gesloten buffer werd alsnog verzonden')

-- Ook één editie gaat naar het gedeelde Python-beleid. Lua mag niet zelf
-- besluiten dat B of K nooit gecontroleerd hoeft te worden.
for _, code in ipairs({ 'B', 'K' }) do
  local single = buffer()
  local before = runs
  ai._check_duplicate_stage(single, { code }, 'importeren', function(ok) approved = ok end)
  assert(runs == before + 1, 'client sloeg één editie over vóór het Python-beleid')
  pending(true, { performed = false, candidates = {} })
  settled(single)
  assert(approved and not ai._duplicate_check_is_current(single), 'beleidsmatig overgeslagen is niet uitgevoerd')
end
-- Een geannuleerde échte doublure (kandidaten aanwezig) breekt ook alle andere
-- lopende AI-taken op dit artikel af. Een annulering zonder kandidaten (bv.
-- netwerkfout of leeg resultaat) doet dat niet.
local original_cancel = ai.cancel_ai
local cancel_calls = {}
ai.cancel_ai = function(target)
  table.insert(cancel_calls, target)
  return true
end

local with_candidates = buffer()
ai._check_duplicate_stage(with_candidates, { 'B', 'D' }, 'herschrijven', function(ok) approved = ok end)
pending(false, {
  version = 1,
  performed = true,
  candidates = { { key = 'join:899', headline = 'Batavia aan land' } },
})
settled(with_candidates)
assert(approved and not ai._duplicate_check_is_current(with_candidates), 'sluiten blokkeerde bewerken of gaf publicatietoestemming')
assert(#ai._ignored_duplicate_keys(with_candidates) == 0,
  'annuleren onthield de kandidaat ten onrechte als genegeerd')
assert(#cancel_calls == 0, 'sluiten bij bewerken stopte onafhankelijke AI-taken')

local empty_cancel = buffer()
ai._check_duplicate_stage(empty_cancel, { 'B', 'D' }, 'herschrijven', function(ok) approved = ok end)
pending(false, { version = 1, performed = true, candidates = {} })
settled(empty_cancel)
assert(#cancel_calls == 0, 'annulering zonder kandidaten brak ten onrechte AI-taken af')

-- Doorgaan met een getoonde kandidaat onthoudt diens stabiele sleutel. Na een
-- inhoudswijziging draait de controle opnieuw, maar de oude kandidaat gaat als
-- uitsluiting mee. Een nieuwe kandidaat kan wel worden getoond en toegevoegd.
local remembered = buffer()
ai._check_duplicate_stage(remembered, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
pending(true, {
  version = 1,
  performed = true,
  candidates = { { key = 'join:900', headline = 'Eerder beoordeeld bericht' } },
})
settled(remembered)
assert(approved, 'doorgaan na kandidaat werd niet geaccepteerd')
assert(vim.deep_equal(ai._ignored_duplicate_keys(remembered), { 'join:900' }),
  'genegeerde kandidaatsleutel werd niet onthouden')

vim.api.nvim_buf_set_lines(remembered, -1, -1, false, { 'Nieuwe inhoud voor hercontrole.' })
ai._check_duplicate_stage(remembered, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
assert(command_has_pair(last_command, '--ignore-key', 'join:900'),
  'latere controle sloot de eerder genegeerde kandidaat niet uit')
pending(true, {
  version = 1,
  performed = true,
  candidates = { { key = 'article:B:901', headline = 'Nieuwe kandidaat' } },
})
settled(remembered)
assert(vim.deep_equal(
  ai._ignored_duplicate_keys(remembered),
  { 'article:B:901', 'join:900' }
), 'nieuwe kandidaat werd niet naast de eerdere uitsluiting onthouden')


-- Een herschreven artikel moet opnieuw langs de controle. Een ruwe importmail
-- vol opmaak levert heel andere zoekwoorden op dan het afgeronde artikel, dus
-- een goedkeuring op de ruwe tekst zegt niets over de tekst die online gaat.
local rewritten = buffer()
ai._check_duplicate_stage(rewritten, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
pending(true, success)
settled(rewritten)
assert(ai._duplicate_check_is_current(rewritten), 'geslaagde controle werd niet onthouden')

local before_rewrite = runs
ai._check_duplicate_stage(rewritten, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
assert(runs == before_rewrite, 'onveranderde tekst werd onnodig opnieuw gecontroleerd')

vim.api.nvim_buf_set_lines(rewritten, 0, -1, false, {
  'e: B, D', '', '=== ARTIKEL ===', '', 'Batavia krijgt groot onderhoud', '',
  'LELYSTAD - Het schip gaat maanden in de steigers.',
})
assert(not ai._duplicate_check_is_current(rewritten), 'herschreven tekst gold nog als gecontroleerd')

ai._check_duplicate_stage(rewritten, { 'B', 'D' }, 'verzenden', function(ok) approved = ok end)
assert(runs == before_rewrite + 1, 'herschreven artikel ging ongecontroleerd naar verzenden')
pending(true, success)
settled(rewritten)
assert(ai._duplicate_check_is_current(rewritten), 'controle op de nieuwe tekst werd niet onthouden')

ai.cancel_ai = original_cancel
ai._duplicate_stage_runner = original_runner
ai._calendar_edition_resolver = original_calendar_resolver
ai._agenda_duplicate_candidates = original_agenda_candidates
vim.system = original_system
print 'duplicate stages: OK'
