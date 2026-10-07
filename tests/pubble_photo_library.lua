-- V2 image-library results share selection/race guards, without a fake article.
local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local requests, opened = {}, {}
vim.notify = function() end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return { kill = function() end }
end
dialog.input = function(opts, done)
  assert(opts.default:find('Bron: Beeldbank', 1, true))
  done(opts.default)
end
dialog.confirm = function() return 1 end
require('ordered_browser').open_urls = function(urls) opened[#opened + 1] = urls[1]; return true end
local function reply(data)
  requests[#requests].done({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local function key(value) vim.fn.maparg(value, 'n', false, true).callback() end
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(source)
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
local editor = 'Bron: Beeldbank\nOnderwerp: hond\nPlaats: Zwolle\nUitsluiten:'
local photo = { schema_version = 2, source_kind = 'image_library', source_article_id = vim.NIL,
  image_metadata_id = 517929, source_title = 'hond.jpg', source_key = 'image:517929',
  edition = 'Beeldbank', date = '', preview_url = '',
  source_url = 'https://brugmedia.pubble.nl/image-library?image=517929', caption = '', credit = 'Pixabay' }
photos.open(source)
reply({ version = 2, query = 'hond', editor_text = editor, field_help = 'Bron kiezen' })
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text == editor)
reply({ version = 2, fields = { subject = 'hond', place = 'Zwolle', exclude = '', source = 'images' },
  query = 'hond Zwolle / hond / Zwolle',
  editor_text = editor, photos = { photo }, candidates = { photo }, next_offset = 4, query_strategy = 2,
  groups = { { source_key = 'image:517929', source_title = 'hond.jpg', photos = { photo } } },
  policy_note = 'Beeldbank: geen 112-filter.' })
local display = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(display:find('Geen direct voorbeeld', 1, true))
assert(display:find('geen 112-filter', 1, true))
vim.api.nvim_win_set_cursor(0, { 5, 0 })
key('o')
assert(opened[1] == photo.source_url, 'fallback must open supplied Pubble image page')
key('x')
assert(vim.json.decode(requests[#requests].opts.stdin).hidden_sources[1] == 'image:517929')
reply({ version = 2, photos = {}, groups = {} })
key('u')
reply({ version = 2, photos = { photo }, groups = { { source_key = 'image:517929', source_title = 'hond.jpg', photos = { photo } } } })
key(']p')
local previous = vim.json.decode(requests[#requests].opts.stdin).previous
assert(previous.version == 2 and previous.fields.source == 'images')
reply({ version = 2, photos = { photo }, groups = { { source_key = 'image:517929', source_title = 'hond.jpg', photos = { photo } } } })
vim.api.nvim_win_set_cursor(0, { 5, 0 })
key('<CR>')
local selection = vim.json.decode(requests[#requests].opts.stdin)
assert(selection.photo.source_article_id == vim.NIL)
reply({ version = 2, markdown = 'b:\nc: Pixabay\n\n=== ARTIKEL ===\n\nKop\n\nTekst.\n' })
assert(vim.api.nvim_get_current_buf() == source)
assert(vim.api.nvim_buf_get_lines(source, 1, 2, false)[1] == 'c: Pixabay')
print('pubble photo library: OK')
