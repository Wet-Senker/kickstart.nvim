local ai = require 'ai_text'
local original_runner = ai._duplicate_stage_runner
local runs, pending, temporary, options = 0, nil, nil, nil
ai._duplicate_stage_runner = function(command, callback, opts)
  runs, pending, temporary, options = runs + 1, callback, command[2], opts
  assert(command[3] == '--json' and command[4] == '--editions', 'actiecontract ontbreekt')
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
  assert(vim.wait(1000, function() return (vim.b[buf].pending_jobs or 0) == 0 end), 'pending_jobs bleef hangen')
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
assert(approved and not vim.b[buf].pubble_duplicate_check_completed, 'fout is ten onrechte afgerond')
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
assert(approved and vim.b[fallback].pubble_duplicate_check_completed, 'send-vangnet faalde')

local stale = buffer()
ai._check_duplicate_stage(stale, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.api.nvim_buf_set_lines(stale, -1, -1, false, { 'Nieuwe inhoud tijdens de vergelijking.' })
vim.b[stale].send_requested = true
assert(not options.is_current(), 'tekstwijziging niet opgemerkt')
pending(true, success)
settled(stale)
assert(not approved and not vim.b[stale].pubble_duplicate_check_completed, 'oude tekst geldt als gecontroleerd')
assert(not vim.b[stale].send_requested, 'geannuleerde controle start uitgestelde verzending')

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
assert(not approved and not vim.b[cancelled].pubble_duplicate_check_completed, 'annuleren werd onthouden als goedkeuring')

-- Een handmatige kalenderstart tijdens de controle wordt uitgesteld. Alleen
-- doorgaan na de doubluremelding hervat hem; annuleren maakt geen AI-kosten.
local original_resume = ai._resume_deferred_calendar
local resumed = 0
ai._resume_deferred_calendar = function(target)
  assert(vim.api.nvim_buf_is_valid(target), 'ongeldige buffer hervat')
  resumed = resumed + 1
end
local waiting_calendar = buffer()
ai._check_duplicate_stage(waiting_calendar, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.api.nvim_set_current_buf(waiting_calendar)
ai.articlemeta_calendar_buffer()
assert(vim.b[waiting_calendar].calendar_ai_waiting_for_duplicate == true, 'kalender-AI wacht niet op doublurebesluit')
assert(vim.b[waiting_calendar].calendar_ai_running ~= true, 'kalender-AI startte tijdens doublurecontrole')
pending(true, success)
settled(waiting_calendar)
assert(resumed == 1, 'goedgekeurde doublurecontrole hervatte kalender-AI niet')

local abandoned_calendar = buffer()
ai._check_duplicate_stage(abandoned_calendar, { 'B', 'D' }, 'importeren', function(ok) approved = ok end)
vim.api.nvim_set_current_buf(abandoned_calendar)
ai.articlemeta_calendar_buffer()
pending(false, success)
settled(abandoned_calendar)
assert(resumed == 1, 'geannuleerde doublurecontrole startte alsnog kalender-AI')
assert(vim.b[abandoned_calendar].calendar_ai_waiting_for_duplicate ~= true, 'geannuleerd kalenderverzoek bleef hangen')
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
  assert(approved and not vim.b[single].pubble_duplicate_check_completed, 'beleidsmatig overgeslagen is niet uitgevoerd')
end
ai._duplicate_stage_runner = original_runner
print 'duplicate stages: OK'
