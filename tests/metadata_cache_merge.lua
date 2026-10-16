package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local original_system, original_send = vim.system, ai.pubble_send
local function run(mode)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = { '---', 'media: {selected_image: {image_metadata_id: 99}}', '---',
    'e: B', '=== ARTIKEL ===', 'Kop', 'KAMPEN - Tekst.' }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].cached_metadata = { '---', 'newspaper: {working_title: Kop}', '---' }
  vim.b[buf].cached_metadata_source = 'e: B\n=== ARTIKEL ===\nKop\nKAMPEN - Tekst.'
  local callback, input, count = nil, nil, 0
  vim.system = function(command, opts, cb)
    count = count + 1
    assert(vim.tbl_contains(command, '--merge-cached-metadata'))
    input = vim.json.decode(opts.stdin)
    callback = cb
    return { kill = function() end }
  end
  original_send(buf)
  assert(callback and count == 1, 'brongebonden cache werd niet samengevoegd')
  assert(input.markdown:find('image_metadata_id: 99', 1, true))
  local resumed = 0
  ai.pubble_send = function(b) assert(b == buf); resumed = resumed + 1 end
  if mode == 'changed' then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere tekst.' })
  end
  local merged = '---\nmedia: {selected_image: {image_metadata_id: 99}}\nnewspaper: {working_title: Kop}\n---\n'
    .. input.source
  callback({ code = mode == 'error' and 1 or 0, stdout = merged, stderr = 'testfout' })
  assert(vim.wait(1000, function() return not vim.b[buf].metadata_merge_pending end))
  if mode == 'ok' then
    assert(resumed == 1 and vim.b[buf].cached_metadata == nil)
    assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') == merged)
  else
    assert(resumed == 0 and vim.b[buf].cached_metadata ~= nil)
    local result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    assert(not result:find('working_title', 1, true))
    if mode == 'changed' then assert(result:find('Nieuwere tekst.', 1, true)) end
  end
  ai.pubble_send = original_send
end
run('ok')
run('changed')
run('error')
vim.system, ai.pubble_send = original_system, original_send
print('metadata cache merge: OK')
