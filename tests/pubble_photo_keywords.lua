local photos = require 'pubble_photos'
local requests, inputs = {}, {}
vim.notify = function() end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return { kill = function() end }
end
local editor = 'Bron: Beide\nZoekwoorden: biljart, Kampen'
require('user_dialog').input = function(opts, done)
  inputs[#inputs + 1] = opts
  assert(opts.vim_edit and opts.priority)
  assert(opts.default == editor)
  assert(not opts.prompt:find('zoekwoorden en plaats', 1, true))
  done(opts.default)
end
local function reply(data)
  requests[#requests].done({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.' })
local before = vim.api.nvim_buf_get_lines(source, 0, -1, false)
photos.open(source)
reply({ version = 2, editor_text = editor, query = 'biljart' })
assert(#inputs == 1)
assert(vim.json.decode(requests[#requests].opts.stdin).editor_text == editor)
reply({ version = 2, editor_text = editor, query = 'biljart Kampen / biljart / Kampen',
  fields = { subject = 'biljart, Kampen', place = '', exclude = '', source = 'both' },
  candidates = {}, photos = {}, groups = {}, query_strategy = 2 })
vim.fn.maparg('b', 'n', false, true).callback()
local payload = vim.json.decode(requests[#requests].opts.stdin)
assert(payload.editor_text == "Bron: Artikelfoto's\nZoekwoorden: biljart, Kampen",
  'bronwissel voegde een plaatsveld toe of veranderde de zoekwoorden')
reply({ version = 2, editor_text = payload.editor_text,
  fields = { subject = 'biljart, Kampen', place = '', exclude = '', source = 'articles' },
  candidates = {}, photos = {}, groups = {} })
vim.fn.maparg('q', 'n', false, true).callback()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), before))
print('pubble photo keywords: OK')
