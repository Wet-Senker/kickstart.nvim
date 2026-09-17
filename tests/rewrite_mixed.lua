package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require 'ai_text'
local review = ai._edition_review
local dialog = require 'user_dialog'
local original_system, original_select = vim.system, dialog.select
local source = 'Bronkop\n\nIn IJsselmuiden en Dronten zijn energieprojecten.'
local requested, streamers, callbacks = {}, {}, {}
local function wait(predicate) assert(vim.wait(5000, predicate, 10), 'gemengde flow bleef hangen') end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split('e: all\n\n=== ARTIKEL ===\n\n' .. source, '\n'))
ai._mark_duplicate_check_done(buf)
vim.b[buf].calendar_autodetect_suppressed = true
ai._capture_import_baseline(buf)
dialog.select = function(items, opts, done)
  assert(opts.prompt:find('IJsselmuiden', 1, true) and opts.prompt:find('Dronten', 1, true))
  assert(opts.prompt:find('geen bewijs', 1, true))
  assert(items[2]:find('overige', 1, true) and items[#items] == 'Annuleren')
  assert(opts.default == 2)
  done(items[2], 2)
end
vim.system = function(command, opts, callback)
  if command[1] == 'bash' then error('overbodige tussenherschrijving') end
  if command[2] == 'krantversie' or command[2] == 'krantversie_algemeen' then
    assert(opts.stdin == source, 'definitieve tekst kreeg niet het origineel')
    local code = command[4]:match('^([^,]+)')
    requested[code] = command
    local body = { code .. ' kop', '', '**Een definitieve intro.**', '' }
    for i = 1, 7 do
      table.insert(body, string.rep('Deze definitieve alinea bevat concrete informatie over de projecten. ', 12))
      table.insert(body, '')
      if i == 3 then table.insert(body, '**Projecten**'); table.insert(body, '') end
    end
    callback { code = 0, stdout = table.concat(body, '\n'), stderr = '' }
    return { kill = function() end }
  end
  if command[2] == 'tussenkopjes' then error('losse tussenkopjesaanvraag') end
  if command[2] == 'streamer' then
    local code = assert(opts.stdin:match('^([A-Z]+) kop'))
    streamers[code] = (streamers[code] or 0) + 1
    callbacks[code] = callback
    return { kill = function() end }
  end
  -- De echte lokale Python-resolver en het echte workspacecontract, geen HTTP.
  if not callback or command[2] == 'inspect' or vim.tbl_contains(command, '--resolve-editions')
      or command[2] == '-m' then return original_system(command, opts, callback) end
  callback { code = 0, stdout = '', stderr = '' }
  return { kill = function() end }
end
ai.rewrite_article_buffer()
wait(function() return callbacks.B and callbacks.D and callbacks.SW end)
assert(vim.tbl_count(requested) == 3 and vim.tbl_count(streamers) == 3, 'niet precies drie unieke teksten/opmaakaanvragen')
assert(requested.SW[2] == 'krantversie_algemeen' and requested.SW[4] == 'SW,ST,Z,K')
assert(not review._review_buffers[buf], 'review startte vóór complete opmaak')
for code, callback in pairs(callbacks) do callback { code = 0, stdout = 'Streamer ' .. code, stderr = '' } end
wait(function() return review._review_buffers[buf] ~= nil end)
local entries = review._review_buffers[buf]
assert(vim.tbl_count(entries) == 6 and entries.B and entries.D and entries.SW
  and entries.ST and entries.Z and entries.K, 'niet één reviewbuffer per krant')
assert(#vim.api.nvim_tabpage_list_wins(0) == 6)
local general = vim.b[entries.SW].edition_variant
assert(table.concat(general.editions, ',') == 'SW')
assert(general.name:find('De Swollenaer', 1, true))
assert(text(entries.SW):find('> Streamer SW', 1, true))
assert(text(entries.ST) == text(entries.SW) and text(entries.Z) == text(entries.SW)
  and text(entries.K) == text(entries.SW), 'algemene tekst werd niet naar iedere krantbuffer gekopieerd')
for _, code in ipairs { 'B', 'D', 'SW', 'ST', 'Z', 'K' } do
  local done = false
  review.sync(entries[code], true, function(ok) assert(ok); done = true end)
  wait(function() return done end)
end
assert(vim.b[buf].edition_workspace_ready, 'zes goedkeuringen maakten niet alle zes kranten klaar')
assert(ai._send_safeguard_reason(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) == nil,
  'gereviewde varianten vroegen onterecht goedkeuring voor de ongewijzigde gedeelde bron')
local done = false
vim.api.nvim_buf_set_lines(entries.SW, -1, -1, false, { 'Redactionele wijziging.' })
review.sync(entries.SW, false, function(ok) assert(ok); done = true end)
wait(function() return done end)
assert(not vim.b[buf].edition_workspace_ready, 'edit bleef stil goedgekeurd')
assert(not text(buf):find('shared-editions:', 1, true), 'nieuwe flow maakte toch een gedeelde reviewbuffer')
review.close(buf, true)
vim.system, dialog.select = original_system, original_select
print 'rewrite mixed: OK'
