local agenda = require 'agenda_menu'
local notifications = {}
vim.notify = function(message) table.insert(notifications, message) end
local hooks = {}
package.loaded.ai_text = {
  set_publication_success_hook = function(buf, callback) hooks[buf] = callback end,
}

local function make_batch(id)
  local sources = {}
  for _, code in ipairs { 'B', 'SW', 'ST', 'Z', 'D', 'K' } do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'hide'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      'e: ' .. code, 'agenda: nee', '', '=== ARTIKEL ===', '',
      '# Weekend ' .. code, '', 'Eigen inhoud ' .. code, '',
      '## Facebook', '', 'Socialtekst ' .. code,
    })
    vim.b[buf].weekend_batch_id = id
    table.insert(sources, { buf = buf, edition = code })
  end
  local batch = { id = id, sources = sources, now = '2026-10-09T10:00:00+02:00' }
  agenda._weekend_batches[id] = batch
  return batch
end

local function prepare(batch)
  local controller
  agenda.prepare_weekend_batch_send(batch.sources[1].buf, function(buf) controller = buf end)
  assert(vim.wait(5000, function() return controller ~= nil end, 10), vim.inspect(notifications))
  return controller, table.concat(vim.api.nvim_buf_get_lines(controller, 0, -1, false), '\n')
end

-- :bd can leave a valid, but unloaded buffer; :bw wipes it entirely.
local batch = make_batch('selection')
local deleted = batch.sources[2].buf
vim.api.nvim_set_current_buf(deleted)
vim.cmd 'bd!'
assert(not vim.api.nvim_buf_is_loaded(deleted), ':bd did not unload test buffer')
vim.api.nvim_buf_delete(batch.sources[3].buf, { force = true })
local controller, combined = prepare(batch)
assert(combined:find('e: B, Z, D, K', 1, true), combined)
assert(not combined:find('Eigen inhoud SW', 1, true), 'deleted SW still included')
assert(not combined:find('Eigen inhoud ST', 1, true), 'wiped ST still included')
for _, code in ipairs { 'B', 'Z', 'D', 'K' } do
  assert(combined:find('Eigen inhoud ' .. code, 1, true), 'hidden loaded source omitted: ' .. code)
  assert(combined:find('Socialtekst ' .. code, 1, true), 'edition social text lost: ' .. code)
end
hooks[controller]()
assert(not vim.api.nvim_buf_is_loaded(deleted), 'success reloaded deleted buffer')
assert(not vim.b[deleted].weekend_batch_sent, 'deleted source marked sent')
assert(notifications[#notifications]:find('4 website', 1, true), 'incorrect sent count')

-- Before any CMS attempt, cached controllers must not resurrect deleted editions.
batch = make_batch('reprepare')
local old_controller = prepare(batch)
vim.api.nvim_buf_delete(batch.sources[1].buf, { force = true })
local new_controller
agenda.prepare_weekend_batch_send(batch.sources[2].buf, function(buf) new_controller = buf end)
assert(vim.wait(5000, function() return new_controller ~= nil end, 10))
assert(new_controller ~= old_controller, 'stale controller reused')
combined = table.concat(vim.api.nvim_buf_get_lines(new_controller, 0, -1, false), '\n')
assert(not combined:find('Eigen inhoud B', 1, true), 'deleted primary resurrected')
assert(combined:find('e: SW, ST, Z, D, K', 1, true), combined)

-- Once publication has started, preserve controller and IDs on retry.
assert(agenda.mark_weekend_batch_send_started(new_controller))
local retried
agenda.prepare_weekend_batch_send(batch.sources[2].buf, function(buf) retried = buf end)
assert(retried == new_controller, 'retry discarded durable controller')
vim.api.nvim_buf_delete(batch.sources[3].buf, { force = true })
retried = nil
agenda.prepare_weekend_batch_send(batch.sources[2].buf, function(buf) retried = buf end)
assert(not retried, 'partially published batch silently rebuilt')
assert(notifications[#notifications]:find('publicatiepoging', 1, true), 'retry warning missing')
vim.api.nvim_buf_delete(new_controller, { force = true })
agenda.prepare_weekend_batch_send(batch.sources[2].buf, function() error('lost IDs recreated') end)
assert(notifications[#notifications]:find('herstel', 1, true), 'lost controller warning missing')

-- Selection is checked again just before the first actual CMS call.
batch = make_batch('before-write')
controller = prepare(batch)
vim.api.nvim_buf_delete(batch.sources[2].buf, { force = true })
assert(not agenda.mark_weekend_batch_send_started(controller), 'stale selection allowed at CMS boundary')
assert(not batch.send_started, 'blocked write froze selection')
controller, combined = prepare(batch)
assert(not combined:find('Eigen inhoud SW', 1, true))
assert(agenda.mark_weekend_batch_send_started(controller))

-- A single surviving edition is valid too, retaining the source metadata.
batch = make_batch('single')
vim.api.nvim_buf_set_lines(batch.sources[1].buf, 0, 0, false, {
  '---', 'calendar_disabled: true', 'media:', '  editorial_asset: weekend-overview', '---', '',
})
for index = 2, #batch.sources do vim.api.nvim_buf_delete(batch.sources[index].buf, { force = true }) end
controller, combined = prepare(batch)
assert(combined:find('e: B', 1, true) and not combined:find('## Editieversies', 1, true))
assert(combined:find('editorial_asset: weekend-overview', 1, true), 'single-edition photo metadata lost')
assert(combined:find('Socialtekst B', 1, true))

-- A :bd during the asynchronous bundling invalidates the complete snapshot.
local real_system = vim.system
local pending
vim.system = function(_, opts, callback)
  pending = { opts = opts, callback = callback }
end
batch = make_batch('race')
local ready = false
agenda.prepare_weekend_batch_send(batch.sources[1].buf, function() ready = true end)
vim.api.nvim_set_current_buf(batch.sources[2].buf)
vim.cmd 'bd!'
pending.callback { code = 0, stdout = vim.json.encode { message = 'stale' } }
assert(vim.wait(1000, function() return not batch.preparing end, 10))
assert(not ready, 'removed buffer sent from stale snapshot')

-- Empty selection never starts a bundling subprocess or sends anything.
batch = make_batch('empty')
for _, source in ipairs(batch.sources) do
  vim.api.nvim_buf_delete(source.buf, { force = true, unload = true })
end
pending = nil
agenda.prepare_weekend_batch_send(batch.sources[1].buf, function() error('empty send') end)
assert(not pending, 'empty selection started a subprocess')
vim.system = real_system
print('weekend_batch_selection: OK')
