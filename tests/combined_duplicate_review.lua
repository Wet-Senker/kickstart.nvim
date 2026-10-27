local ai = require 'ai_text'
local duplicates = require 'pubble_duplicates'
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local native_system = vim.system
local response = {
  version = 1, combined = true, performed = true, history_complete = true, errors = {},
  checks = {
    web = { performed = true, requested = true, complete = true },
    agenda = { performed = true, requested = true, complete = true, bron = 'ruwe tekst' },
  },
  candidates = {
    { kind = 'web', key = 'join:123', headline = 'Webbericht', variants = {
      { kind = 'web', publication = 'De Brug', headline = 'Webbericht', display_date_short = '20-10-2099' },
    } },
    { kind = 'agenda', key = 'agenda:pair456', review_key = 'pair456', headline = 'Agenda-item', variants = {
      { kind = 'agenda', publication = 'De Brug', headline = 'Agenda-item', display_date_short = '20-10-2099' },
    } },
  },
}
local calls, windows, last_command = 0, 0, nil
vim.system = dofile('tests/helpers/calendar_core.lua')(function(command, _, done)
  if vim.tbl_contains(command, '--resolve-editions') then
    done { code = 0, stdout = vim.json.encode { editions = { 'B' }, names = { B = 'De Brug' }, has_explicit_editions = true } }
    return {}
  end
  if command[2] == 'krantversie' or command[2] == 'journalistiek_schrijven' then
    done { code = 0, stdout = 'Nieuwe concertkop\n\nKAMPEN - Nieuwe tekst.' }
    return {}
  end
  assert(command[1]:match('pubble%-duplicates$') and vim.tbl_contains(command, '--with-agenda'))
  calls, last_command = calls + 1, command
  local payload = vim.deepcopy(response)
  if vim.tbl_contains(command, '--skip-web') then
    payload.checks.web.requested = false
    payload.candidates = { payload.candidates[2] }
  end
  done { code = 0, stdout = vim.json.encode(payload), stderr = '' }
  return {}
end)
local original_show = duplicates.show
duplicates.show = function(...)
  windows = windows + 1
  return original_show(...)
end
ai._agenda_duplicate_candidates = function() error('tweede agenda-uitlezing op ongewijzigde bron') end
ai.cancel_ai = function() error('review stopte onafhankelijke AI-taak') end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Concert', '',
    'KAMPEN - Concert op 20 oktober 2099 om 19.30 uur.' })
  return buf
end
local function wait(test) assert(vim.wait(2000, test, 5), 'gezamenlijke review bleef wachten') end
local function key(buf, name)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs == name then mapping.callback(); return end
  end
  error('toets ontbreekt: ' .. name)
end
local function dialog()
  wait(function() return vim.api.nvim_buf_get_name(0):find('Pubble doublurecontrole', 1, true) ~= nil end)
  return vim.api.nvim_get_current_buf()
end
local function idle(buf) wait(function() return (vim.b[buf].pending_jobs or 0) == 0 end) end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

-- Vroeg n is één keuze: bewerken gaat meteen verder, zonder publicatieakkoord.
local buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
local review = dialog()
assert(text(review):find('Agenda', 1, true) and text(review):find('Web', 1, true))
key(review, 'n')
idle(buf)
assert(approved == true and text(buf):find('agenda: nee', 1, true))
assert(calls == 1 and windows == 1, 'web en agenda openden afzonderlijke controles')
assert(not vim.api.nvim_buf_is_valid(review), 'vroeg n vroeg nog een tweede besluit')
assert(not ai._duplicate_check_is_current(buf), 'bewerken zonder agenda gaf webpublicatie vrij')
assert(#ai._ignored_duplicate_keys(buf) == 0, 'vroeg n negeerde webtreffers voor definitieve verzending')
local agenda_ok
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) agenda_ok = ok end)
assert(agenda_ok == true)
-- Dezelfde invoer kan daarna met ar verder zonder dezelfde vroege vraag;
-- definitief verzenden moet juist wél een eigen beoordeling krijgen.
ai._check_duplicate_stage(buf, { 'B' }, 'herschrijven', function(ok) approved = ok end)
assert(approved and calls == 1)
approved = nil
ai._check_duplicate_stage(buf, { 'B' }, 'verzenden', function(ok) approved = ok end)
review = dialog()
assert(approved == nil and calls == 2)
key(review, 'q'); idle(buf)
assert(approved == false, 'bewerkingsakkoord werd als publicatieakkoord gebruikt')

-- v keurt beide getoonde kanalen goed; daarna geen losse agendavraag.
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
key(dialog(), 'v'); idle(buf)
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) agenda_ok = ok end)
assert(approved and agenda_ok and calls == 3 and windows == 3)
assert(vim.deep_equal(ai._ignored_duplicate_keys(buf), { 'join:123' }), 'agenda-identiteit kwam in webuitsluitingen')

-- q bij vroege review laat bewerken doorgaan, zonder automatisch agendablok.
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
key(dialog(), 'q'); idle(buf)
assert(approved and vim.b[buf].calendar_autodetect_suppressed)
assert(not ai._duplicate_check_is_current(buf) and not text(buf):find('## Kalender', 1, true))

-- Eindcontrole vóór staging doet beide samen; q stopt alleen de verzending.
buf, approved = source(), nil
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) approved = ok end, nil, true)
review = dialog()
assert(text(review):find('Verzending afbreken', 1, true))
key(review, 'q'); idle(buf)
assert(approved == false)
approved = nil
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) approved = ok end, nil, true)
key(dialog(), 'n')
assert(approved == nil)
key(vim.api.nvim_get_current_buf(), 'v'); idle(buf)
assert(approved and text(buf):find('agenda: nee', 1, true), 'n werd niet vóór de publicatiekopie toegepast')

-- m bij agenda bewaart uitsluitend de bestaande inhoudsgebonden paarsleutel.
local marks = {}
require('duplicate_review').mark_agenda = function(key_value, done) marks[#marks + 1] = key_value; done(true) end
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
review = dialog()
for index, line in ipairs(vim.api.nvim_buf_get_lines(review, 0, -1, false)) do
  if line:find('Agenda%-item') then vim.api.nvim_win_set_cursor(0, { index, 0 }); break end
end
key(review, 'm')
assert(marks[1] == 'pair456' and approved == nil)
key(review, 'v'); idle(buf)
assert(approved)

-- Gewijzigde editie tijdens de review stopt de alleen-lezen controle niet.
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
review = dialog()
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: K' })
key(review, 'v'); idle(buf)
assert(approved == true and not ai._duplicate_check_is_current(buf))
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'e: K')

-- De echte aw-ingang beoordeelt vóór staging. Een reeds gecontroleerd web
-- wordt niet opnieuw uitgelezen; n wordt toegepast vóór de hervatte send.
buf = source()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Kalender', '', 'Titel: Concert', 'Datum: 2099-10-20' })
vim.b[buf].calendar_transition_tick = vim.api.nvim_buf_get_changedtick(buf)
ai._mark_duplicate_check_done(buf)
ai._calendar_edition_resolver = function(_, _, done) done { editions = { 'B' } } end
local real_send, resumed = ai.pubble_send, 0
ai.pubble_send = function(target, _, reviewed)
  assert(target == buf and reviewed == true and text(buf):find('agenda: nee', 1, true))
  resumed = resumed + 1
end
real_send(buf)
review = dialog()
assert(vim.tbl_contains(last_command, '--skip-web'), 'aw deed een al actuele webcontrole opnieuw')
key(review, 'q'); idle(buf)
assert(resumed == 0 and not vim.b[buf].calendar_send_review_pending)
local resolver_done, before_calls = nil, calls
ai._calendar_edition_resolver = function(_, _, done) resolver_done = done end
real_send(buf)
assert(resolver_done and calls == before_calls)
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: K' })
resolver_done { editions = { 'B' } }
assert(calls == before_calls and not vim.b[buf].calendar_send_review_pending,
  'laat editieantwoord startte controle/verzending voor de verkeerde krant')
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: B' })
vim.b[buf].calendar_transition_tick = vim.api.nvim_buf_get_changedtick(buf)
ai._calendar_edition_resolver = function(_, _, done) done { editions = { 'B' } } end
real_send(buf)
key(dialog(), 'n'); idle(buf)
assert(resumed == 1 and not text(buf):find('## Kalender', 1, true))
ai.pubble_send = real_send

-- n vóór ar moet ook de volledige herschrijving overleven: de oude sectie
-- mag niet via de eerder bewaarde staart alsnog teruggezet worden.
buf = source()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Kalender', '', 'Titel: Oude agenda', 'Datum: 2099-10-20' })
local post, applied = ai._post_full_article_rewrite, false
ai._post_full_article_rewrite = function() applied = true end
ai.rewrite_article_buffer()
review = dialog()
key(review, 'n')
wait(function() return applied end); idle(buf)
assert(text(buf):find('Nieuwe concertkop', 1, true) and text(buf):find('agenda: nee', 1, true))
assert(not text(buf):find('## Kalender', 1, true), 'ar zette de zojuist afgewezen agenda terug')
ai._post_full_article_rewrite = post

-- Ook bij een onvolledige vroege controle volstaat n voor verder bewerken;
-- de fout wordt daarmee niet als een geslaagde publicatiecontrole onthouden.
response.errors, response.history_complete = { 'web: niet bereikbaar' }, false
response.checks.web.complete = false
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
key(dialog(), 'n'); idle(buf)
assert(approved and text(buf):find('agenda: nee', 1, true))
assert(not ai._duplicate_check_is_current(buf) and #ai._ignored_duplicate_keys(buf) == 0)
response.errors, response.history_complete, response.checks.web.complete = {}, true, true

-- Een fout in één kanaal houdt de andere treffers zichtbaar en vereist v/q.
response.errors = { 'agenda: site onbereikbaar' }
response.checks.agenda.complete = false
response.history_complete = false
response.candidates = { response.candidates[1] }
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'verzenden', function(ok) approved = ok end)
review = dialog()
assert(text(review):find('site onbereikbaar', 1, true))
key(review, 'm')
assert(approved == nil, 'm gaf stil toestemming voor een mislukte andere controle')
key(review, 'q'); idle(buf)
assert(approved == false)
-- Bij een mislukte agenda-uitlezing mag de redacteur bewust zonder agenda
-- doorgaan, maar web moet nog steeds apart beoordeeld zijn.
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'verzenden', function(ok) approved = ok end)
review = dialog()
key(review, 'n')
assert(approved == nil and not text(review):find('site onbereikbaar', 1, true))
key(review, 'm'); idle(buf)
assert(approved and text(buf):find('agenda: nee', 1, true))
-- Beleidsmatig overgeslagen web is niet uitgevoerd; later een andere editie
-- kiezen moet nog altijd de centrale webcontrole kunnen activeren.
response.candidates, response.errors = {}, {}
response.checks.web.performed = false
response.checks.agenda.complete = true
buf, approved = source(), nil
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
wait(function() return approved ~= nil end); idle(buf)
assert(approved and not ai._duplicate_check_is_current(buf), 'overgeslagen web werd als uitgevoerd gecachet')
-- Een expliciete hercontrole moet ook een eerder bewerkingsakkoord overrulen.
vim.b[buf].pubble_duplicate_editing_review = ai._duplicate_editing_revision(buf, { 'B' })
local before_recheck = calls
ai.recheck_duplicates(buf)
wait(function() return calls == before_recheck + 1 end); idle(buf)
vim.system, duplicates.show = native_system, original_show
print('combined duplicate review: OK')
