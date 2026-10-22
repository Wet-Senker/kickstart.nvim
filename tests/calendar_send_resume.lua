-- Echte aw-/resolver-/taakgrenzen, zonder externe subprocessen/publicatie.
-- Vooral de cache-hit is belangrijk: die roept de reviewcallback synchroon
-- aan terwijl de resolver zijn taak pas via vim.schedule afmeldt.
local ai = require('ai_text')
local jobs = require('buffer_jobs')
local revision = require('buffer_revision')
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local real_send = ai.pubble_send
local original_reject = ai.reject_calendar
local resolutions, duplicate_checks, resumed = 0, 0, 0
local resolver_done, duplicate_done, duplicate_options
local current, edit_after_approval

vim.system = function(command, _, done)
  assert(vim.tbl_contains(command, '--resolve-editions'), 'onverwachte externe actie')
  resolutions = resolutions + 1
  resolver_done = done
  return {}
end
ai._duplicate_stage_runner = function(_, done, options)
  duplicate_checks = duplicate_checks + 1
  duplicate_done, duplicate_options = done, options
end
ai.pubble_send = function(buf, reconciled, reviewed)
  if reviewed then
    assert(buf == current and reconciled, 'verkeerde verzendvoortzetting')
    for _, task in ipairs(jobs.active(buf)) do
      assert(task.action ~= 'Artikel · Edities bepalen' and task.action ~= 'Artikel · Doublures controleren',
        'verzenden wacht op zijn eigen afgeronde reviewtaak')
    end
    assert(not vim.b[buf].calendar_send_review_pending, 'reviewpoort bleef dicht')
    if jobs.count(buf) > 0 then return real_send(buf, reconciled, reviewed) end
    resumed = resumed + 1
    return -- Staging/publicatie is bewust niet onderdeel van deze offline test.
  end
  return real_send(buf, reconciled, reviewed)
end
local function drain()
  local done = false
  vim.schedule(function() vim.schedule(function() vim.schedule(function() done = true end) end) end)
  assert(vim.wait(1000, function() return done end, 5), 'eventqueue bleef hangen')
end
local function source(cached)
  current = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(current)
  -- Na ar is een editie toegevoegd; BR moet via de echte resolveraanroep mee.
  local lines = { 'e: SW, BR', '', '=== ARTIKEL ===', '', 'Concert in Hedon', '',
    'ZWOLLE - Een concert op 31 oktober 2099.', '', '## Kalender', '',
    'Titel: Concert', 'Datum: 2099-10-31', 'Stad: Zwolle' }
  vim.api.nvim_buf_set_lines(current, 0, -1, false, lines)
  vim.b[current].calendar_transition_tick = vim.api.nvim_buf_get_changedtick(current)
  ai._mark_duplicate_check_done(current)
  if cached then
    vim.b[current].agenda_duplicate_checked_fingerprint = vim.fn.sha256('SW,B\n'
      .. table.concat(require('article_notices').content_lines(lines), '\n'))
    assert(ai._agenda_duplicate_is_current(current, { 'SW', 'B' }))
  end
  resolver_done, duplicate_done, duplicate_options = nil, nil, nil
  return current
end
local function resolve()
  assert(resolver_done, 'resolver niet gestart')
  resolver_done { code = 0, stdout = vim.json.encode { editions = { 'SW', 'B' } }, stderr = '' }
  drain()
end
local success = { combined = true, checks = {
  web = { requested = false, complete = true },
  agenda = { requested = true, complete = true, bron = 'kalenderblok' },
}, candidates = {} }

-- Cache-hit: exact één resolver en één goedgekeurde voortzetting, ook als
-- intussen opnieuw aw is gedrukt of al een algemeen verzendverzoek wachtte.
for _, waiting in ipairs({ false, true }) do
  local buf = source(true)
  local before_resolve, before_resume = resolutions, resumed
  ai.pubble_send(buf)
  assert(jobs.count(buf) == 1 and vim.b[buf].calendar_send_review_pending)
  ai.pubble_send(buf)
  vim.b[buf].send_requested = waiting
  resolve()
  assert(resolutions == before_resolve + 1 and resumed == before_resume + 1,
    'cache-hit herstartte de editiecontrole of verzond meer dan eenmaal')
  assert(not vim.b[buf].send_requested and jobs.count(buf) == 0)
end
assert(duplicate_checks == 0, 'cache-hit deed opnieuw een doublurecall')

-- Ander achtergrondwerk mag nog wel uitlopen: de gewone wachtpoort blijft
-- werken en herneemt daarna de actuele controles, zonder eindeloze lus.
local buf = source(true)
ai.pubble_send(buf)
local other_job = jobs.start(buf, 'Onafhankelijke achtergrondtaak')
local before_resume = resumed
resolve()
assert(resumed == before_resume and vim.b[buf].send_requested and jobs.count(buf) == 1)
assert(jobs.finish(other_job))
ai._on_buffer_jobs_idle(buf)
resolve()
assert(resumed == before_resume + 1 and jobs.count(buf) == 0 and not vim.b[buf].send_requested)

-- Nieuwe controle: ook haar eigen taak moet vóór de voortzetting afgemeld zijn.
buf = source(false)
ai.pubble_send(buf); resolve()
assert(duplicate_checks == 1 and duplicate_done and jobs.count(buf) == 1)
vim.b[buf].send_requested = true
before_resume = resumed
local before_resolve = resolutions
duplicate_done(true, success); drain()
assert(resumed == before_resume + 1 and resolutions == before_resolve)
assert(not vim.b[buf].send_requested and jobs.count(buf) == 0)

-- n verwijdert de kalender al vóór afronding. De idle-herstart mag daardoor
-- niet langs de reviewpoort lopen en een tweede verzendflow openen.
ai.reject_calendar = function(target)
  vim.api.nvim_buf_set_lines(target, 7, -1, false, {})
  vim.api.nvim_buf_set_lines(target, 1, 1, false, { 'agenda: nee' })
end
buf = source(false)
ai.pubble_send(buf); resolve()
vim.b[buf].send_requested = true
before_resume, before_resolve = resumed, resolutions
local skipped = vim.deepcopy(success)
skipped.agenda_decision = 'skip'
duplicate_done(true, skipped); drain()
assert(resumed == before_resume + 1 and resolutions == before_resolve)
assert(not vim.b[buf].send_requested and jobs.count(buf) == 0)
ai.reject_calendar = original_reject

-- q stopt deze poging, ook wanneer een automatische hervatting wachtte.
buf = source(false)
ai.pubble_send(buf); resolve()
vim.b[buf].send_requested = true
before_resume = resumed
duplicate_done(false, success); drain()
assert(resumed == before_resume and not vim.b[buf].calendar_send_review_pending)
assert(not vim.b[buf].send_requested and jobs.count(buf) == 0)

-- Een wijziging tussen goedkeuring en de geplande voortzetting stopt veilig.
-- Injecteer deze exact in dat eventqueue-venster, niet tijdens de review.
buf = source(false)
ai.pubble_send(buf); resolve()
local capture = revision.capture
revision.capture = function(target)
  local result = capture(target)
  if target == buf and edit_after_approval then
    edit_after_approval = false
    vim.schedule(function()
      vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: B' })
    end)
  end
  return result
end
edit_after_approval = true
vim.b[buf].send_requested = true
before_resume = resumed
duplicate_done(true, success); drain()
revision.capture = capture
assert(resumed == before_resume and not vim.b[buf].calendar_send_review_pending)
assert(not vim.b[buf].send_requested and jobs.count(buf) == 0,
  'nieuwe bewerking werd genegeerd of liet een wachtende verzending achter')

-- Een resolverfout moet de poort eveneens vrijgeven, zonder verzendvervolg.
buf = source(false)
ai.pubble_send(buf)
vim.b[buf].send_requested = true
before_resume = resumed
resolver_done { code = 1, stdout = '', stderr = 'bewuste fout' }; drain()
assert(resumed == before_resume and jobs.count(buf) == 0)
assert(not vim.b[buf].calendar_send_review_pending and not vim.b[buf].send_requested)
-- Daarna kan de gebruiker bewust een nieuwe poging starten.
vim.b[buf].calendar_transition_tick = vim.api.nvim_buf_get_changedtick(buf)
ai.pubble_send(buf); resolve()
duplicate_done(true, success); drain()
assert(resumed == before_resume + 1 and jobs.count(buf) == 0)

buf = source(false)
ai.pubble_send(buf)
vim.b[buf].send_requested = true
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: SW' })
before_resume = resumed
resolve()
assert(resumed == before_resume and not vim.b[buf].calendar_send_review_pending)
assert(not vim.b[buf].send_requested and jobs.count(buf) == 0)

buf = source(false)
ai.pubble_send(buf)
before_resume = resumed
vim.api.nvim_buf_delete(buf, { force = true })
resolve()
assert(resumed == before_resume and jobs.count(buf) == 0, 'gesloten buffer werd alsnog verzonden')
print('calendar send resume: OK')
