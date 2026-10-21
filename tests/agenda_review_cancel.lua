-- Echte clientcallbacks: voorbereiden en publiceren zijn verschillende keuzes.
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local ai = require 'ai_text'
local original_system = vim.system
local original_candidates = ai._agenda_duplicate_candidates
local replies, answer, checks = {}, nil, 0
local complete = { code = 0, stdout = [[---
calendar:
  event_candidate: true
  calendar_ready: true
  calendar_title: Samenzangavond
  event_date: '2099-10-31'
  start_time: '19:30'
  location_name: De Hoeksteen
  city: IJsselmuiden
  calendar_body: Er worden psalmen gezongen.
---
]], stderr = '' }
local data = { version = 1, performed = true, bron = 'ruwe tekst', candidates = {
  { editie = 'B', bestaand_titel = 'Samenzangavond', bestaand_datum = '2099-10-31' },
} }
vim.system = dofile('tests/helpers/calendar_core.lua')(function(cmd, _, done)
  assert(cmd[2] == '--calendar' and vim.tbl_contains(cmd, '--calendar-explicit'),
    'onverwachte externe opdracht: ' .. table.concat(cmd, ' '))
  replies[#replies + 1] = done
  return { kill = function() error('een keuze stopte een onafhankelijk proces') end }
end)
ai._agenda_duplicate_candidates = function(_, _, done)
  checks = checks + 1
  done(vim.deepcopy(data))
end
ai._agenda_duplicate_confirm = function(_, _, done) answer = done end
local function wait(test) assert(vim.wait(2000, test, 5), 'agenda-test bleef wachten') end
local function drain()
  local done = false; vim.schedule(function() done = true end); wait(function() return done end)
end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '',
    'Samenzangavond met Urker tintje', '', 'IJSSELMUIDEN - Op 31 oktober is een zangavond.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function review(buf, choice, publication)
  if publication then ai._mark_duplicate_check_done(buf) end -- deze test isoleert agenda
  answer = nil
  local result
  ai._check_agenda_duplicates(buf, { 'B' }, function(ok) result = ok end, nil, publication)
  assert(answer and result == nil, 'de beoordeling werd niet geopend')
  answer(choice)
  return result
end
local function manual(buf)
  vim.api.nvim_set_current_buf(buf)
  local count = #replies
  ai.articlemeta_calendar_buffer()
  wait(function() return #replies == count + 1 end)
  assert(text(buf):find('## Kalender', 1, true), 'ac liet geen invulbaar werkblok achter')
  return replies[#replies]
end
local function idle(buf) wait(function() return (vim.b[buf].pending_jobs or 0) == 0 end); drain() end

-- Vroeg q laat bewerken doorgaan, maar maakt niet alsnog automatisch agenda.
local buf = source()
assert(review(buf, nil) == true)
assert(vim.b[buf].agenda_review_cancelled == true)
assert(not text(buf):find('## Kalender', 1, true) and not text(buf):find('agenda: nee', 1, true))
assert(#replies == 0, 'sluiten startte kalender-AI')
assert(review(source(), false) == true)
local declined = vim.api.nvim_get_current_buf()
assert(text(declined):find('agenda: nee', 1, true), 'n werd niet duurzaam vastgelegd')

-- ac overrulet zowel uitstel als blijvend nee, zonder doublurevraag.
for _, target in ipairs { buf, declined } do
  local before_checks = checks
  local reply = manual(target)
  assert(text(target):find('agenda: ja', 1, true) and not text(target):find('agenda: nee', 1, true))
  reply(complete); idle(target)
  assert(text(target):find('Titel: Samenzangavond', 1, true))
  assert(checks == before_checks, 'ac startte toch een automatische doublurebeoordeling')
end

-- q bij verzending stopt alleen deze poging. Opnieuw aw mag opnieuw beoordelen.
assert(review(buf, nil, true) == false)
assert(text(buf):find('Titel: Samenzangavond', 1, true), 'verzendannulering verwijderde werktekst')
assert(review(buf, true, true) == true, 'een afgebroken verzendpoging blokkeerde iedere retry')

-- Twee expliciete pogingen: een laat oud resultaat mag het nieuwe niet vervangen.
buf = source()
local old_reply = manual(buf)
local new_reply = manual(buf)
old_reply(complete); drain()
assert(not text(buf):find('Titel: Samenzangavond', 1, true), 'oude AI-uitkomst werd na herstart toegepast')
new_reply(complete); idle(buf)
assert(text(buf):find('Titel: Samenzangavond', 1, true))

-- Een handmatig verwijderd blok blijft na opslaan/heropenen bewust uit.
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
for index, line in ipairs(lines) do
  if line == '## Kalender' then
    while #lines >= index do table.remove(lines) end
    break
  end
end
local filename = vim.fn.tempname() .. '.md'
vim.fn.writefile(lines, filename)
vim.api.nvim_buf_delete(buf, { force = true })
buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(filename))
local reconciled
ai._calendar_transition(buf, 'reconcile', {}, function(value) reconciled = value end)
wait(function() return reconciled ~= nil end)
assert(reconciled.status == 'removed' and text(buf):find('agenda: nee', 1, true))
assert(not text(buf):find('## Kalender', 1, true))
local before_replies = #replies
ai._calendar_autodetect(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
drain()
assert(#replies == before_replies, 'heropenen maakte een verwijderd kalenderblok opnieuw')

-- Een wijziging tijdens de laatste publicatiecontrole vraagt opnieuw controle.
local fresh = source()
ai._mark_duplicate_check_done(fresh)
local callback
ai._agenda_duplicate_candidates = function(_, _, done) callback = done end
local publication
ai._check_agenda_duplicates(fresh, { 'B' }, function(ok) publication = ok end, nil, true)
vim.api.nvim_buf_set_lines(fresh, -1, -1, false, { 'Nieuwere tekst' })
callback(data)
assert(publication == false, 'verzending ging verder na bronwijziging tijdens controle')

-- Een mislukte uitlezing zonder kandidaten is geen stilzwijgend groen licht.
ai._agenda_duplicate_candidates = function(_, _, done)
  done { version = 1, performed = true, errors = { 'site niet bereikbaar' }, candidates = {} }
end
publication = nil
local failed_review = source()
ai._mark_duplicate_check_done(failed_review)
ai._check_agenda_duplicates(failed_review, { 'B' }, function(ok) publication = ok end, nil, true)
assert(publication == false, 'mislukte eindcontrole werd als publicatietoestemming gebruikt')

-- Bestaand transport leest het voorstel zonder vooraf de buffer te veranderen.
local prepared = { '=== ARTIKEL ===', '', 'Voorstel', '', '## Kalender', '', 'Titel: Voorstel' }
local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
local called = 0
vim.system = function(cmd, _, done)
  called = called + 1
  assert(vim.tbl_contains(cmd, 'artikel-doublures'))
  assert(vim.deep_equal(vim.fn.readfile(cmd[6]), prepared))
  done { code = 0, stdout = vim.json.encode(data), stderr = '' }
  return {}
end
local received
original_candidates(buf, { 'B' }, function(value) received = value end, prepared)
wait(function() return received ~= nil end)
assert(called == 1 and vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
vim.system = original_system
print('agenda review cancel: OK')
