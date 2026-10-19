local activity = require 'article_activity'
local notifications = require 'texttools_notify'
local log = require 'workflow_log'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Archiefartikel' })
local native = vim.system
local callbacks, calls = {}, 0
vim.system = function(_, opts, done)
  assert(opts.texttools_activity == nil, 'presentatiecontract lekte naar subprocess')
  calls = calls + 1
  callbacks[calls] = done
  return { kill = function() end }
end
local function settled()
  vim.wait(40, function() return false end)
end
local function count()
  local total = 0
  for _ in pairs(activity.snapshot(buf).tasks) do
    total = total + 1
  end
  return total
end
require('archive_context').search(buf)
assert(activity.statusline(buf):find('Archief zoeken', 1, true), 'echte archiefactie meldde geen lopende taken')
assert(count() == 1, 'archiefactie niet exact eenmaal geregistreerd')
callbacks[1] { code = 1, stderr = 'Zoeken mislukt' }
settled()
assert(count() == 0 and activity.snapshot(buf).attention, 'archieffout niet geregistreerd')
require('archive_context').search(buf)
local unrelated = log.start(buf, 'Foto uploaden')
notifications.bind(buf, function() notifications.notify('Foto mislukt', vim.log.levels.ERROR) end, { action = unrelated.action, id = unrelated.action_id })()
log.finish(unrelated, 'failed')
callbacks[2] { code = 0, stdout = '{"shown":[],"articles":[]}' }
settled()
local state = activity.snapshot(buf)
assert(not state.issues['Archief zoeken'], 'succesvolle herhaling liet archieffout staan')
assert(state.issues['Foto uploaden'], 'archiefsucces wiste ongerelateerde fotofout')
assert(state.attention.message == 'Foto mislukt', 'juiste resterende fout niet zichtbaar')

-- Traces worden niet dubbel geteld. De scope overleeft geneste bind/schedule.
local trace = log.start(buf, 'Metadata samenvoegen')
notifications.system(
  { 'articlemeta' },
  log.with_environment({ text = true }, trace),
  notifications.bind(buf, function()
    notifications.schedule(function() notifications.notify('Metadatafout', vim.log.levels.ERROR) end)
  end)
)
assert(count() == 1, 'getraceerde taak dubbel geteld')
callbacks[3] { code = 1 }
log.finish(trace, 'failed')
settled()
assert(activity.snapshot(buf).issues['Metadata samenvoegen'], 'geneste callback verloor actiescope')
local newer = log.start(buf, 'Metadata samenvoegen')
notifications.bind(buf, function() notifications.notify('Nieuwe metadatafout', vim.log.levels.ERROR) end, { action = newer.action, id = newer.action_id })()
log.finish(newer, 'failed')
notifications.bind(buf, function() notifications.workflow('Oud succes', nil, { kind = 'success' }) end, { action = trace.action, id = trace.action_id })()
assert(activity.snapshot(buf).issues['Metadata samenvoegen'].message == 'Nieuwe metadatafout', 'oud succes wiste nieuwe fout')

local retry = log.start(buf, 'Metadata samenvoegen')
notifications.system({ 'articlemeta' }, log.with_environment({}, retry), function()
  notifications.schedule(function() notifications.workflow('Metadata toegepast', nil, { kind = 'success' }) end)
end)
callbacks[4] { code = 0 }
log.finish(retry, 'succeeded')
settled()
assert(not activity.snapshot(buf).issues['Metadata samenvoegen'], 'correcte herhaling loste presentatie niet op')
assert(activity.snapshot(buf).issues['Foto uploaden'], 'andere actie onterecht opgelost')
notifications.bind(buf, function() notifications.notify('Late oude fout', vim.log.levels.ERROR) end, { action = trace.action, id = trace.action_id })()
local last = activity.snapshot(buf).entries[#activity.snapshot(buf).entries]
assert(last.historical and not activity.snapshot(buf).issues['Metadata samenvoegen'], 'oude fout werd opnieuw actueel')
assert(calls == 4, 'tracking voegde subprocessen toe')

-- Een mislukte start laat geen eeuwig lopende taak achter.
vim.system = function() error 'kan niet starten' end
assert(not pcall(notifications.system, { 'gemiste-opdracht' }, {}, function() end))
assert(count() == 0, 'mislukte start liet actieve taak achter')
assert(activity.snapshot(buf).issues['gemiste-opdracht'], 'startfout niet leesbaar')
notifications.notify('Ongekoppelde fout', vim.log.levels.ERROR)
notifications.workflow('Vul een veld in', nil, { attention = true })
assert(activity.snapshot(buf).attention.level == vim.log.levels.ERROR, 'instructie verdrong ongerelateerde ongekoppelde fout')
vim.system = native
print 'activity tracking: OK'
