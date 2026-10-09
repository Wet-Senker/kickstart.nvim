-- Compact photo results, source switching and editable search fields.
local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local real_input = dialog.input
local requests, defaults = {}, {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  local request = { cmd = cmd, opts = opts, callback = callback }
  requests[#requests + 1] = request
  return { kill = function() request.killed = true end }
end
dialog.input = function(opts, done)
  defaults[#defaults + 1] = opts.default
  assert(opts.vim_edit)
  done(opts.default)
end
local function reply(data)
  data.version = 2
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
local editor = "Bron: Artikelfoto's\nOnderwerp: hond, honden\nPlaats: Milligerplas"
local a = { image_metadata_id = 1, source_article_id = 100, source_title = 'Bron A',
  edition = 'SW', date = '', caption = '<p>Hond</p>', display_caption = 'Hond',
  credit = 'F', preview_url = 'https://images.pubble.cloud/example.jpg' }
local b = vim.tbl_extend('force', a, { image_metadata_id = 2, caption = 'Tweede hond', display_caption = 'Tweede hond' })
photos.open()
reply({ query = 'hond', editor_text = editor })
assert(defaults[1] == editor)
reply({ query = 'hond', editor_text = editor,
  fields = { source = 'articles', subject = 'hond, honden', place = 'Milligerplas', exclude = '' },
  candidates = { a, b }, photos = { a, b }, next_offset = 6, source = 'articles' })
local picker = vim.api.nvim_get_current_buf()
local function display() return table.concat(vim.api.nvim_buf_get_lines(picker, 0, -1, false), '\n') end
assert(display():find('2 gevonden', 1, true))
assert(display():find('Tweede hond', 1, true))
assert(not display():find('Gevonden via:', 1, true))
assert(vim.fn.maparg('o', 'n') == '' and vim.fn.maparg('x', 'n') == '')
assert(vim.fn.maparg('u', 'n') == '' and vim.fn.maparg('<Tab>', 'n') == '')
for _, k in ipairs({ '/', 'n', 'g', 'v' }) do assert(vim.fn.maparg(k, 'n') == '') end
key('p')
local browse = requests[#requests]
assert(#vim.json.decode(browse.opts.stdin).photos == 2)
key('b')
assert(browse.killed)
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text:find('Bron: Beeldbank', 1, true))
reply({ query = 'hond', editor_text = 'Bron: Beeldbank\nOnderwerp: hond, honden\nPlaats: Milligerplas',
  fields = { source = 'images', subject = 'hond, honden', place = 'Milligerplas', exclude = '' },
  photos = { a }, candidates = { a }, source = 'images' })
assert(display():find('Beeldbank', 1, true))
key('b')
local both_editor = 'Bron: Beide\nOnderwerp: hond, honden\nPlaats: Milligerplas'
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text:find('Bron: Beide', 1, true))
reply({ query = 'hond', editor_text = both_editor,
  fields = { source = 'both', subject = 'hond, honden', place = 'Milligerplas', exclude = '' },
  photos = { a }, candidates = { a }, source = 'both' })
key('s')
assert(defaults[#defaults] == both_editor)
reply({ query = 'hond', editor_text = both_editor, photos = {}, candidates = {}, source = 'both' })
assert(vim.api.nvim_buf_get_changedtick(source) == tick)
key('q')
assert(vim.api.nvim_get_current_buf() == source)
dialog.input = real_input
photos.open()
reply({ query = 'hond', editor_text = editor })
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.split(editor, '\n')))
assert(vim.b.pubble_photo_source == source)
key('<CR>')
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text == editor)
reply({ query = 'hond', editor_text = editor, photos = {}, candidates = {}, source = 'articles' })
key('q')
print('pubble photo filters: OK')
