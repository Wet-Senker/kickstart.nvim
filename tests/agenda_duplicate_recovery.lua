dofile('tests/helpers/notice_clock.lua')
local ai, activity, duplicates = require('ai_text'), require('article_activity'), require('pubble_duplicates')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: SW', '', '=== ARTIKEL ===', '', 'Poker', '', 'ZWOLLE - Voorronde.' })
  vim.api.nvim_set_current_buf(buf)
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function wait(test) assert(vim.wait(2000, test, 5), 'agendawaarschuwing bleef hangen') end
local warning = 'Agenda-doublurecontrole was niet volledig: calendar.calendar_ready must be true'
local buf = buffer()
local original_candidates = ai._agenda_duplicate_candidates
local data = { version = 1, performed = false, candidates = {}, errors = { 'calendar.calendar_ready must be true' } }
ai._agenda_duplicate_candidates = function(_, _, done) done(data) end
ai._check_agenda_duplicates(buf, { 'SW' }, function() end)
wait(function() return text(buf):find(warning, 1, true) end)
assert(activity.snapshot(buf).issues['agenda-review'])
assert(not text(buf):find('geen vergelijking nodig', 1, true), 'fout werd ook als normale overslaan-uitkomst getoond')
data = { version = 1, performed = true, candidates = {}, errors = {}, bron = 'kalenderblok' }
ai._check_agenda_duplicates(buf, { 'SW' }, function() end)
wait(function() return not text(buf):find(warning, 1, true) end)
assert(not activity.snapshot(buf).issues['agenda-review'])
assert(activity.snapshot(buf).entries[1].message == warning, 'historische fout verdween uit logboek')
ai._agenda_duplicate_candidates = original_candidates

local native_system, native_show = vim.system, duplicates.show
local reply, calls = nil, 0
vim.system = function(_, _, done) calls, reply = calls + 1, done; return {} end
duplicates.show = function(_, done) done(false) end
local function report(status)
  return { version = 1, combined = true, performed = true, candidates = {}, errors = {},
    checks = { agenda = { performed = status == 'checked', complete = status ~= 'incomplete', errors = {} } },
    summary = { version = 1, status = 'checked', message = 'Doublurecontrole: agenda ' .. status,
      channels = { agenda = { status = status, candidate_count = 0 } } } }
end
local function start(target)
  reply = nil
  duplicates.check({ 'offline-check' }, function() end, { buf = target })
  assert(reply)
end
local function finish(payload)
  reply { code = 0, stdout = vim.json.encode(payload), stderr = '' }
end
for _, status in ipairs { 'checked', 'incomplete', 'skipped' } do
  buf = buffer()
  activity.record(buf, warning, vim.log.levels.WARN, { action = 'Agenda · Doublurecontrole', notice_key = 'agenda-review' })
  activity.record(buf, 'Fotocredit ontbreekt.', vim.log.levels.WARN, { action = 'Foto' })
  wait(function() return text(buf):find(warning, 1, true) end)
  start(buf)
  finish(report(status))
  wait(function() return text(buf):find('Doublurecontrole: agenda ' .. status, 1, true) end)
  assert((activity.snapshot(buf).issues['agenda-review'] == nil) == (status == 'checked'))
  assert((not text(buf):find(warning, 1, true)) == (status == 'checked'))
  assert(activity.snapshot(buf).issues.Foto, 'agendacontrole wiste een andere fout')
end
-- Een oude uitvoeringsfout (zonder vaste sleutel) kan ook worden afgehandeld.
buf = buffer()
activity.record(buf, warning, vim.log.levels.WARN, { action = 'Agenda · Doublurecontrole' })
start(buf)
finish(report('checked'))
wait(function() return not activity.snapshot(buf).issues['Agenda · Doublurecontrole'] end)

-- Een later teruggekeerde scan mag een nieuwere agendafout niet afvinken.
buf = buffer()
activity.record(buf, warning, vim.log.levels.WARN, { action = 'Agenda · Doublurecontrole', notice_key = 'agenda-review' })
start(buf)
-- Registreer als actuele poging zoals de echte taakregistratie doet.
activity.start(buf, 'newest', 'Agenda · Doublurecontrole')
activity.record(buf, 'Nieuwere controle mislukt.', vim.log.levels.WARN,
  { action = 'Agenda · Doublurecontrole', notice_key = 'agenda-review', run_id = 'newest' })
activity.finish(buf, 'newest')
local newest = activity.snapshot(buf).issues['agenda-review'].id
finish(report('checked'))
wait(function() return text(buf):find('Doublurecontrole: agenda checked', 1, true) end)
assert(activity.snapshot(buf).issues['agenda-review'].id == newest, 'late scan wiste nieuwere fout')
assert(calls == 5, 'meldingsherstel startte extra processen')
vim.system, duplicates.show = native_system, native_show
print('agenda duplicate recovery: OK')
