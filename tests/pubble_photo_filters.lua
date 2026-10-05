-- Structured search, grouping and session-only hiding use the shared core.
local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local real_input = dialog.input
local requests = {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  local request = { cmd = cmd, opts = opts, callback = callback }
  requests[#requests + 1] = request
  return { kill = function() request.killed = true end }
end
local defaults = {}
dialog.input = function(opts, done)
  defaults[#defaults + 1] = opts.default
  assert(opts.vim_edit)
  done(opts.default)
end
local function reply(data)
  data.version = 1
  requests[#requests].callback({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local function key(k)
  local map = vim.fn.maparg(k, 'n', false, true)
  assert(type(map.callback) == 'function', k)
  map.callback()
end
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Honden bij de plassen', '', 'Tekst' })
local tick = vim.api.nvim_buf_get_changedtick(source)
local editor = 'Onderwerp: hond, honden\nPlaats: Milligerplas\nUitsluiten: avondvierdaagse'
local a = { image_metadata_id = 1, source_article_id = 100, source_title = 'Bron A',
  edition = 'SW', date = '', caption = '<p>Hond</p>', display_caption = 'Hond',
  credit = 'F', preview_url = 'https://images.pubble.cloud/example.jpg', match_reason = 'bijschrift: hond' }
local b = vim.tbl_extend('force', a, { image_metadata_id = 2, caption = 'Tweede hond', display_caption = 'Tweede hond' })
local c = vim.tbl_extend('force', a, { image_metadata_id = 3, source_article_id = 200, source_title = 'Bron B' })
local groups = { { source_key = 'SW:100', source_title = 'Bron A', photos = { a, b } },
  { source_key = 'SW:200', source_title = 'Bron B', photos = { c } } }
photos.open()
reply({ query = 'oude suggestie', editor_text = editor })
assert(defaults[1] == editor)
assert(requests[2].cmd[4] == 'search' and requests[2].cmd[5] == '--fields')
assert(vim.json.decode(requests[2].opts.stdin).editor_text == editor)
reply({ query = 'hond Milligerplas / honden Milligerplas', editor_text = editor,
  candidates = { a, b, c }, photos = { a, b, c }, groups = groups, next_offset = 6 })
local picker = vim.api.nvim_get_current_buf()
local function display() return table.concat(vim.api.nvim_buf_get_lines(picker, 0, -1, false), '\n') end
assert(display():find('2 foto’s', 1, true))
assert(not display():find('Tweede hond', 1, true), 'initially collapse per source')
assert(display():find('Bijschrift: Hond', 1, true), 'display plain metadata')
vim.api.nvim_win_set_cursor(0, { 5, 0 })
local count = #requests
key('<Tab>')
assert(#requests == count and display():find('Tweede hond', 1, true), 'expand without subprocess/network')
for _, k in ipairs({ '/', 'n', 'g', 'v' }) do assert(vim.fn.maparg(k, 'n') == '') end
key('p')
local browse = requests[#requests]
assert(#vim.json.decode(browse.opts.stdin).photos == 3, 'browser includes collapsed photos')
key('x')
assert(browse.killed, 'filter change invalidates browser selection')
assert(requests[#requests].cmd[4] == 'view')
assert(vim.deep_equal(vim.json.decode(requests[#requests].opts.stdin).hidden_sources, { 'SW:100' }))
reply({ photos = { c }, groups = { groups[2] }, filtered_photos = 2 })
assert(not display():find('Bron A', 1, true))
key('p')
assert(#vim.json.decode(requests[#requests].opts.stdin).photos == 1)
key('u')
assert(requests[#requests].cmd[4] == 'view')
assert(#vim.json.decode(requests[#requests].opts.stdin).hidden_sources == 0)
reply({ photos = { a, b, c }, groups = groups, filtered_photos = 0 })
assert(display():find('Bron A', 1, true))
key(']p')
assert(requests[#requests].cmd[4] == 'search' and requests[#requests].cmd[7] == '6')
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text == editor)
reply({ query = 'hond Milligerplas', editor_text = editor, candidates = {}, photos = {}, groups = {} })
key('s')
assert(defaults[#defaults] == editor, 'editing retains the three fields')
reply({ query = 'hond Milligerplas', editor_text = editor, candidates = {}, photos = {}, groups = {} })
assert(vim.api.nvim_buf_get_changedtick(source) == tick, 'filtering never edits article')
key('q')
assert(vim.api.nvim_get_current_buf() == source)
-- The real input is a Vim buffer with three independently editable lines.
dialog.input = real_input
photos.open()
reply({ query = 'hond', editor_text = editor })
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.split(editor, '\n')))
assert(vim.b.pubble_photo_source == source)
vim.cmd('normal! 2G0f:lv$h')
vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'Plaats: ' })
key('<CR>')
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text:find('Plaats: \n', 1, true))
assert(vim.api.nvim_buf_get_changedtick(source) == tick)
reply({ query = 'hond', editor_text = editor, candidates = {}, photos = {}, groups = {} })
key('q')
print('pubble photo filters: OK')
