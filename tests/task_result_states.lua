local shown, serial = {}, 0
package.preload['fidget.progress'] = function()
  return { handle = { create = function(spec)
    serial = serial + 1
    local handle = vim.deepcopy(spec)
    handle.token = serial
    function handle:report(change) for key, value in pairs(change) do self[key] = value end end
    function handle:finish() self.done = true end
    shown[serial] = handle
    return handle
  end } }
end
package.preload['fidget.notification'] = function()
  return { remove = function(_, key) shown[key] = nil end,
    clear = function() for key in pairs(shown) do shown[key] = nil end end }
end
local activity = require('article_activity')
local ai = require('ai_text')
local notify = require('texttools_notify')
local log = require('workflow_log')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function wait(test) assert(vim.wait(1000, test, 5), 'taakuitkomst bleef hangen') end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Mijn tekst.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function idle(buf) return not next(activity.snapshot(buf).tasks) and (vim.b[buf].pending_jobs or 0) == 0 end
local native_system = vim.system
local reply, launches = nil, 0
vim.system = dofile('tests/helpers/calendar_core.lua')(function(_, _, done)
  launches, reply = launches + 1, done
  return { is_closing = function() return false end, kill = function() end }
end)
local buf = source()
for _, case in ipairs({ 'applied', 'not_applied', 'failed', 'empty', 'cancelled' }) do
  ai.tekstcheck()
  wait(function() return shown[serial] and not shown[serial].done end)
  local handle = shown[serial]
  assert(handle.title == 'Tekst controleren…' and not handle.title:find('afgerond', 1, true))
  if case == 'not_applied' then vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Eigen nieuwere tekst.' }) end
  if case == 'cancelled' then
    local id, task = next(activity.snapshot(buf).tasks)
    activity.record(buf, 'Een eerdere waarschuwing bij deze taak.', vim.log.levels.WARN,
      { action = task.action, run_id = id })
    assert(ai.cancel_ai(buf))
  end
  reply { code = case == 'failed' and 1 or 0, stdout = case == 'empty' and '' or 'Kop\n\nResultaat.', stderr = 'testfout' }
  wait(function() return idle(buf) end)
  assert(handle.done and handle.message == '')
  if case == 'applied' then assert(handle.title == '✓ Tekst gecontroleerd')
  elseif case == 'not_applied' then
    assert(handle.title == '– Tekstcontrole niet toegepast' and text(buf):find('Eigen nieuwere tekst.', 1, true))
  elseif case == 'cancelled' then assert(handle.title == '– Tekstcontrole geannuleerd')
  else assert(handle.title == '✗ Tekstcontrole mislukt') end
end
assert(launches == 5, 'presentatie startte extra processen')

-- Technisch klaar is geen toegepast succes; gemengde bundels worden geen vinkje.
local one, two = log.start(buf, 'AI · Herschrijven'), log.start(buf, 'AI · Herschrijven')
wait(function() return shown[serial] and not shown[serial].done end)
local mixed = shown[serial]
activity.result(buf, one.action_id, 'failed')
activity.result(buf, two.action_id, 'applied')
log.finish(one, 'failed'); log.finish(two, 'succeeded')
wait(function() return idle(buf) end)
assert(mixed.title == '✗ Herschrijven mislukt', 'laatste succes verborg eerdere fout')
local unknown = log.start(buf, 'AI · Herschrijven')
wait(function() return shown[serial] and not shown[serial].done end)
local unconfirmed = shown[serial]
log.finish(unknown, 'succeeded')
wait(function() return idle(buf) end)
assert(unconfirmed.done and not shown[unconfirmed.token],
  'exitcode 0 zonder bevestiging kreeg een succesvinkje of generieke klaar-melding')

-- Een resultaat dat nog op de doublurekeuze wacht, blijft bezig. Na plaatsing
-- bevestigt dezelfde taak-ID het resultaat; een andere taak wordt niet geraakt.
local deferred = log.start(buf, 'AI · Kalender')
wait(function() return shown[serial] and not shown[serial].done end)
local calendar = shown[serial]
activity.defer_result(buf, deferred.action_id)
log.finish(deferred, 'succeeded')
local drained = false; vim.schedule(function() drained = true end); wait(function() return drained end)
assert(not calendar.done and activity.snapshot(buf).tasks[deferred.action_id])
activity.result(buf, deferred.action_id, 'applied')
assert(calendar.done and calendar.title == '✓ Kalendergegevens verwerkt')

local resolver, check = ai._calendar_edition_resolver, ai._check_agenda_duplicates
local resolve
ai._calendar_edition_resolver = function(_, _, done) resolve = done end
ai._check_agenda_duplicates = function(_, _, done) done(true) end
local pending_buf = source()
ai.articlemeta_calendar_buffer()
wait(function() return launches == 6 end)
local pending_calendar = shown[serial]
local editing = require('buffer_jobs').start(pending_buf, 'Herschrijven')
local unrelated = log.start(pending_buf, 'AI · Herschrijven')
for index, line in ipairs(vim.api.nvim_buf_get_lines(pending_buf, 0, -1, false)) do
  if line == 'Mijn tekst.' then
    vim.api.nvim_buf_set_lines(pending_buf, index, index, false, { 'Een nieuwere eigen alinea.' })
    break
  end
end
reply { code = 0, stdout = table.concat({ '---', 'calendar:', '  event_candidate: true',
  '  calendar_ready: true', '  calendar_title: Concert', "  event_date: '2099-10-21'",
  "  start_time: '20:00'", '  location_name: Kerk', '  city: Kampen', '  calendar_body: Muziek.', '---' }, '\n') }
wait(function() return (vim.b[pending_buf].pending_jobs or 0) == 1 end)
assert(not pending_calendar.done, 'procesexit liep vooruit op de kalenderplaatsing')
assert(vim.b[pending_buf].pending_calendar_task_scope and not pending_calendar.done)
require('buffer_jobs').finish(editing)
ai._apply_pending_calendar_section(pending_buf)
wait(function() return pending_calendar.done end)
assert(pending_calendar.title == '✓ Kalendergegevens verwerkt')
assert(not activity.snapshot(pending_buf).tasks[unrelated.action_id].outcome,
  'kalenderuitkomst gaf een andere taak een succesvinkje')
log.finish(unrelated, 'succeeded')
wait(function() return idle(pending_buf) end)
assert(text(pending_buf):find('Een nieuwere eigen alinea.', 1, true)
  and text(pending_buf):find('## Kalender', 1, true)
  and not text(pending_buf):find('Melding: Kalendergegevens toegevoegd.', 1, true))
assert(launches == 6, 'uitstel startte nogmaals kalender-AI')
ai._calendar_edition_resolver, ai._check_agenda_duplicates = resolver, check

local closed_buf = source()
local closed = log.start(closed_buf, 'AI · Kalender')
wait(function() return shown[serial] and not shown[serial].done end)
activity.defer_result(closed_buf, closed.action_id)
log.finish(closed, 'succeeded')
drained = false; vim.schedule(function() drained = true end); wait(function() return drained end)
vim.api.nvim_buf_delete(closed_buf, { force = true })
assert(not activity.snapshot(closed_buf), 'gesloten uitgestelde verwerking bleef hangen')
vim.system = native_system
print('task result states: OK')
