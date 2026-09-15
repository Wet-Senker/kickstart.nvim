package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require 'ai_text'
local review = ai._edition_review
local original_system = vim.system
local original_choice = ai._edition_mode_choice
local original_variant_runner = ai._edition_variant_runner
local callbacks, requested, workspace_calls = {}, {}, 0
local origin = 'Originele kop\n\nOrigineel persbericht.'
local rewritten = { '# Herschreven kop', '', '**REGIO - Een intro over het onderwerp.**', '' }
for i = 1, 7 do
  table.insert(rewritten, string.rep('Deze alinea beschrijft concrete informatie over energieprojecten. ', 12))
  table.insert(rewritten, '')
end
local function drain(predicate)
  assert(vim.wait(1000, predicate, 10), 'achtergrondstap werd niet afgerond')
end
local function make_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: all', '', '=== ARTIKEL ===', '', 'Originele kop', '', 'Origineel persbericht.',
  })
  vim.b[buf].pubble_duplicate_check_completed = true
  vim.b[buf].calendar_autodetect_suppressed = true
  return buf
end
ai._edition_mode_choice = function() return 2 end
vim.system = function(command, opts, callback)
  if not callback or command[2] == 'inspect' then return original_system(command, opts, callback) end
  if command[1] == 'bash' then
    error('splitsen startte een overbodige tussenherschrijving')
  elseif vim.tbl_contains(command, '--resolve-editions') then
    callback { code = 0, stdout = '{"editions":["B","SW"],"names":["De Brug","De Swollenaer"]}', stderr = '' }
  elseif command[2] == 'tussenkopjes' or command[2] == 'streamer' then
    local code = assert(opts.stdin:match('([A-Z]+) kop'), 'opmaak kreeg niet een definitieve krantversie')
    callbacks[code] = callbacks[code] or {}
    callbacks[code][command[2]] = callback
  else
    callback { code = 0, stdout = '', stderr = '' }
  end
  return { kill = function() end }
end
ai._edition_variant_runner = function(_, code, input, done)
  assert(input == origin, 'versie gebruikte de opgemaakte tekst in plaats van het origineel')
  table.insert(requested, code)
  local body = vim.deepcopy(rewritten)
  body[1] = code .. ' kop'
  table.insert(body, 9, '**Onderwerp ' .. code .. '**')
  table.insert(body, 10, '')
  done(true, table.concat(body, '\n'))
end
review._runner = function(_, action, payload, done)
  assert(action == 'create')
  if payload.markdown:find('Nieuwere tekst van de redacteur.', 1, true) then
    done(false, nil, 'Bron gewijzigd; resultaat niet toegepast.')
    return
  end
  workspace_calls = workspace_calls + 1
  assert(not payload.expected_source:find('> ', 1, true), 'gedeelde tussenversie kreeg opmaak')
  local variants, markdown = {}, payload.markdown .. '\n\n## Editieversies\n'
  for _, code in ipairs(payload.editions) do
    assert(payload.variants[code]:find('> Streamer ' .. code, 1, true), 'versie mist eigen streamer')
    assert(payload.variants[code]:find('**Onderwerp ' .. code .. '**', 1, true), 'versie mist eigen tussenkopje')
    assert(not payload.variants[code]:find('Streamer ' .. (code == 'B' and 'SW' or 'B'), 1, true), 'opmaak van andere krant gebruikt')
    table.insert(variants, { code = code, name = code, content = payload.variants[code], status = 'review' })
    markdown = markdown .. '\n### Editieversie ' .. code .. '\n\n' .. payload.variants[code] .. '\n'
  end
  done(true, { contract_version = 1, markdown = markdown,
    workspace = { schema_version = 2, source_stale = false, ready = false, variants = variants } })
end

local buf = make_buffer()
ai.rewrite_article_buffer()
drain(function() return callbacks.B and callbacks.SW and callbacks.SW.streamer end)
assert(table.concat(requested, ',') == 'B,SW', 'opmaak viel vóór definitieve versie-generatie')
assert(workspace_calls == 0, 'review begon vóór opmaak')
callbacks.B.streamer { code = 0, stdout = 'Streamer B', stderr = '' }
assert(not callbacks.B.tussenkopjes and not callbacks.SW.tussenkopjes, 'tussenkopjes gingen toch via een losse AI-call')
local drained = false
vim.schedule(function() drained = true end)
drain(function() return drained end)
assert(workspace_calls == 0, 'review begon vóór opmaak van de laatste krant')
callbacks.SW.streamer { code = 0, stdout = 'Streamer SW', stderr = '' }
drain(function() return workspace_calls == 1 end)
assert(table.concat(requested, ',') == 'B,SW')
assert(review._review_buffers[buf].B and review._review_buffers[buf].SW, 'reviewbuffers ontbreken')
assert(table.concat(vim.api.nvim_buf_get_lines(review._review_buffers[buf].B, 0, -1, false), '\n'):find('> Streamer B', 1, true))
assert(#vim.api.nvim_tabpage_list_wins(0) == 2, 'krantversies staan niet zichtbaar naast elkaar')
review.close(buf, true)

-- Een echte bron-edit tijdens versieopmaak mag niet worden overschreven.
callbacks, requested = {}, {}
buf = make_buffer()
ai.rewrite_article_buffer()
drain(function() return callbacks.B and callbacks.SW and callbacks.SW.streamer end)
vim.api.nvim_buf_set_lines(buf, 6, 7, false, { 'Nieuwere tekst van de redacteur.' })
for _, code in ipairs { 'B', 'SW' } do
  callbacks[code].streamer { code = 0, stdout = 'Streamer ' .. code, stderr = '' }
end
drained = false
vim.schedule(function() drained = true end)
drain(function() return drained end)
assert(workspace_calls == 1 and not review._review_buffers[buf], 'gewijzigde bron kreeg toch late reviewversies')
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Nieuwere tekst van de redacteur.', 1, true))

vim.system = original_system
ai._edition_mode_choice = original_choice
ai._edition_variant_runner = original_variant_runner
review._runner = nil
print 'rewrite structure race: OK'
