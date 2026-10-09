local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local requests = {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  local r = { cmd = cmd, opts = opts, callback = callback }
  requests[#requests + 1] = r
  return { kill = function() r.killed = true end }
end
local edited
dialog.input = function(opts, done) done(edited or opts.default) end
local function reply(data, code)
  data.version = 1
  requests[#requests].callback({ code = code or 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local function key(k)
  local map = vim.fn.maparg(k, 'n', false, true)
  assert(type(map.callback) == 'function', k)
  map.callback()
end
local function input() return vim.json.decode(requests[#requests].opts.stdin) end
local editor = "Bron: Artikelfoto's\nOnderwerp: hond\nPlaats:"
local fields = { subject = 'hond', place = '', exclude = '', source = 'articles' }
local a = { image_metadata_id = 1, source_article_id = 100, source_title = 'Bron A',
  edition = 'B', date = '', caption = 'Hond', credit = 'F', preview_url = 'https://images.pubble.cloud/example.jpg' }
local b = vim.tbl_extend('force', a, { source_article_id = 200, source_title = 'Bron B' })
local groupa = { source_key = 'B:100', source_title = 'Bron A', photos = { a } }
local groupb = { source_key = 'B:200', source_title = 'Bron B', photos = { b } }
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst' })
local tick = vim.api.nvim_buf_get_changedtick(source)
photos.open()
reply({ query = 'hond', editor_text = editor })
assert(not input().previous)
reply({ query = 'hond', editor_text = editor, fields = fields,
  photos = { a }, candidates = { a }, groups = { groupa }, next_offset = 12, new_photos = 1 })
key('p')
local browse = requests[#requests]
key(']p')
assert(browse.killed)
assert(input().previous.next_offset == 12 and #input().previous.candidates == 1)
local previous = input().previous
reply({}, 1)
key(']p')
assert(vim.deep_equal(input().previous, previous), 'retry retains successful page')
reply({ query = 'hond', editor_text = editor, fields = fields,
  photos = { a }, candidates = { a, b }, groups = { groupa }, next_offset = 24, new_photos = 0 })
local count = #requests
vim.wait(40, function() return false end, 5)
assert(#requests == count, 'no automatic sweep on a duplicate-only page')
assert(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find('1 gevonden', 1, true))
key('p')
assert(#input().photos == 1, 'browser only receives unique candidates')
key('b')
assert(input().editor_text:find('Bron: Beeldbank', 1, true))
assert(not input().previous, 'source switch starts a fresh search')
reply({ query = 'hond', editor_text = 'Bron: Beeldbank\nOnderwerp: hond\nPlaats:',
  fields = { subject = 'hond', place = '', exclude = '', source = 'images' },
  photos = { b }, candidates = { b }, next_offset = 24 })
key(']p')
assert(input().previous.next_offset == 24 and #input().previous.candidates == 1)
reply({ query = 'hond', editor_text = editor, fields = fields,
  photos = { b }, candidates = { a, b }, groups = { groupb }, next_offset = vim.NIL, new_photos = 0 })
edited = "Bron: Artikelfoto's\nOnderwerp: kat\nPlaats:"
key('s')
assert(not input().previous, 'new filters must not reuse old candidates/cursor')
assert(requests[#requests].cmd[7] == '0')
reply({ query = 'kat', editor_text = edited, fields = { subject = 'kat', place = '', exclude = '', source = 'articles' },
  photos = {}, candidates = {}, groups = {}, next_offset = vim.NIL, new_photos = 0 })
assert(vim.api.nvim_buf_get_changedtick(source) == tick)
key('q')
photos.open(source)
reply({ query = 'hond', editor_text = editor })
assert(not input().previous, 'fresh picker has fresh history')
reply({ query = 'hond', editor_text = editor, fields = fields,
  photos = {}, candidates = {}, groups = {}, next_offset = vim.NIL, new_photos = 0 })
key('q')
print('pubble photo pages: OK')
