-- Handmatige hercontrole rapporteert echte uitkomsten, ook zonder popup.
dofile('tests/helpers/notice_clock.lua')
local ai, duplicates = require('ai_text'), require('pubble_duplicates')
local activity = require('article_activity')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'Mijn artikeltekst.' })
local function text(target) return table.concat(vim.api.nvim_buf_get_lines(target or buf, 0, -1, false), '\n') end
local function wait(test) assert(vim.wait(2000, test, 5), 'doublureresultaat bleef hangen: ' .. text()) end
ai._calendar_edition_resolver = function(_, _, done) done { editions = { 'B' } } end
local native_system, pending, calls, shown = vim.system, nil, 0, 0
vim.system = function(command, _, done)
  assert(command[1]:match('pubble%-duplicates$'), 'rapportage startte extra proces')
  calls, pending = calls + 1, done
  return { kill = function() end }
end
duplicates.show = function(_, done) shown = shown + 1; done(false) end
local function report(status, message, web, agenda, errors)
  return { version = 1, combined = true, performed = true, history_complete = not errors, errors = errors or {}, candidates = {},
    checks = { web = { requested = true, complete = true, performed = true },
      agenda = { requested = true, complete = true, performed = true } },
    summary = { version = 1, status = status, message = message, channels = {
      web = web or { status = 'checked', candidate_count = 0 },
      agenda = agenda or { status = 'checked', candidate_count = 0 },
    } } }
end
local function run(payload)
  pending = nil
  ai.recheck_duplicates(buf)
  wait(function() return pending ~= nil end)
  pending { code = 0, stdout = vim.json.encode(payload), stderr = '' }
  wait(function() return (vim.b[buf].pending_jobs or 0) == 0 and text():find(payload.summary.message, 1, true) end)
  assert(not text():find('Doublurecontrole opnieuw gedraaid', 1, true), 'generieke afronding stapelde op')
  local count = 0
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match('^%[12:34%].*Doublurecontrole:') then count = count + 1 end
  end
  assert(count == 1, 'nieuwe controle verving het oude resultaat niet')
end
local empty = report('checked', 'Doublurecontrole: web geen mogelijke doublures; agenda geen mogelijke doublures.')
run(empty)
assert(shown == 0, 'nul treffers opende een leeg keuzescherm')
assert(activity.snapshot(buf).entries[#activity.snapshot(buf).entries].message == empty.summary.message)
assert(text():find('[12:34] ' .. empty.summary.message, 1, true), 'resultaat ontbreekt boven artikel')
assert(not next(activity.snapshot(buf).issues))

local found = report('checked', 'Doublurecontrole: web geen mogelijke doublures; agenda 1 mogelijke doublure.', nil,
  { status = 'checked', candidate_count = 1 })
found.candidates = { { kind = 'agenda', headline = 'GEHEIME KOP', key = 'agenda:1' } }
run(found)
assert(shown == 1 and not text():find('GEHEIME KOP', 1, true))
local partial = report('incomplete', 'Doublurecontrole: web geen mogelijke doublures; agenda onvolledig. Controleer opnieuw met <leader>ad.',
  nil, { status = 'incomplete', candidate_count = 0 }, { 'GEHEIME FOUT' })
partial.checks.agenda.complete = false
run(partial)
assert(activity.snapshot(buf).issues['duplicate-check'], 'deelfout werd schoon resultaat')
local skipped = report('skipped', 'Doublurecontrole: web niet gecontroleerd; agenda niet gecontroleerd.',
  { status = 'skipped', candidate_count = 0 }, { status = 'skipped', candidate_count = 0 })
skipped.performed = false
run(skipped)
assert(not next(activity.snapshot(buf).issues), 'nieuwe expliciete uitkomst liet oude fout staan')
assert(calls == 4, 'resultaatmelding deed extra controles')
local log = table.concat(vim.fn.readfile(require('workflow_log').log_path()), '\n')
assert(log:find('candidate_count', 1, true) and log:find('duplicate_check', 1, true))
assert(not log:find('GEHEIME KOP', 1, true) and not log:find('GEHEIME FOUT', 1, true), 'redactionele tekst lekte naar technisch log')

-- Een late callback na navigatie blijft bij de oorspronkelijke bron.
ai.recheck_duplicates(buf)
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(other)
pending { code = 0, stdout = vim.json.encode(empty), stderr = '' }
wait(function() return text():find(empty.summary.message, 1, true) end)
assert(not text(other):find('Doublurecontrole', 1, true), 'resultaat lekte naar ander artikel')

-- Wijziging tijdens ophalen: toon de scanuitkomst, maar markeer de nieuwe
-- artikeltekst niet als gecontroleerd en start geen impliciete verzending.
vim.api.nvim_set_current_buf(buf)
ai.recheck_duplicates(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere inhoud.' })
pending { code = 0, stdout = vim.json.encode(empty), stderr = '' }
wait(function() return (vim.b[buf].pending_jobs or 0) == 0 and text():find(empty.summary.message, 1, true) end)
assert(not ai._duplicate_check_is_current(buf) and not vim.b[buf].send_requested)

-- Alleen een resultaatregel wijzigen vraagt geen extra kalender-subprocess.
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Kalender', '', 'Titel: Concert' })
vim.b[buf].calendar_transition_tick = vim.api.nvim_buf_get_changedtick(buf)
assert(not ai._calendar_transition_needed(buf))
activity.record(buf, 'Een ander logresultaat.', nil, { inline = true, notice_key = 'test' })
wait(function() return text():find('Een ander logresultaat.', 1, true) end)
assert(not ai._calendar_transition_needed(buf), 'meldregel startte onnodige kalenderverwerking')
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Datum: 2099-10-28' })
assert(ai._calendar_transition_needed(buf), 'echte kalenderwijziging werd genegeerd')
vim.system = native_system
print('duplicate result log: OK')
