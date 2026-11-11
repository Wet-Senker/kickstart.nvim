local photos = require 'pubble_photos'
require('tests.helpers.photo_text')(photos)
local dialog = require 'user_dialog'
local requests = {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  requests[#requests + 1] = { cmd = cmd, opts = opts, callback = callback }
  return { kill = function() end }
end
dialog.input = function(opts, done) done(opts.default) end
local function reply(data)
  data.version = 2
  requests[#requests].callback({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local function key(value) vim.fn.maparg(value, 'n', false, true).callback() end
local function text() return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n') end
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
local fields = { subject = 'fiets', place = '', exclude = '', source = 'stock' }
local editor = "Bron: Stockfoto's\nZoekwoorden: fiets"
local old = { image_metadata_id = 1, source_article_id = vim.NIL, source_kind = 'image_library', schema_version = 2,
  source_title = 'Eerste foto', edition = "Stockfoto's", date = '', caption = 'Eerste fiets', credit = 'Redactie', preview_url = '' }
local new = vim.tbl_extend('force', old, { image_metadata_id = 2, caption = 'Nieuwe fiets' })
photos.open(source)
reply { query = 'fiets', editor_text = editor }
reply { fields = fields, source = 'stock', editor_text = editor, photos = { old }, page_photos = { old },
  candidates = { old }, next_offset = 12, query_strategy = 2 }
assert(text():find('pagina 1', 1, true) and text():find("Stockfoto's", 1, true))
key(']p')
reply { fields = fields, source = 'stock', editor_text = editor, photos = { old, new }, page_photos = { new },
  candidates = { old, new }, next_offset = vim.NIL, query_strategy = 2 }
assert(text():find('pagina 2', 1, true) and text():find('Nieuwe fiets', 1, true))
assert(not text():find('Eerste fiets', 1, true), 'oude foto bleef op de nieuwe pagina staan')
local count = #requests
key('[p')
assert(#requests == count and text():find('Eerste fiets', 1, true) and not text():find('Nieuwe fiets', 1, true))
key(']p')
assert(#requests == count and text():find('Nieuwe fiets', 1, true))
key('p')
local payload = vim.json.decode(requests[#requests].opts.stdin)
assert(payload.page.display_page == 2 and #payload.page.page_history == 2)
assert(#payload.photos == 1 and payload.photos[1].image_metadata_id == 2)
key('b')
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text:find('Bron: Alle', 1, true))
print('pubble photo pagination: OK')
