local photos = require('pubble_photos')
local dialog = require('user_dialog')
local requests, inputs, menus = {}, {}, {}
vim.notify = function() end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }; return {}
end
dialog.input = function(opts, done) inputs[#inputs + 1] = { opts = opts, done = done } end
dialog.select = function(items, opts, done) menus[#menus + 1] = { items = items, opts = opts, done = done } end
local function reply(value, code, error)
  requests[#requests].done({ code = code or 0, stdout = value and vim.json.encode(value) or '', stderr = error or '' })
  vim.wait(30, function() return false end, 5)
end
local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true); assert(type(map.callback) == 'function'); map.callback()
end
local path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' }, path)
vim.cmd('edit ' .. vim.fn.fnameescape(path))
local source = vim.api.nvim_get_current_buf()
photos.open(source)
reply({ version = 2, editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen' })
inputs[1].done(inputs[1].opts.default)
reply({ version = 2, photos = {}, candidates = {}, source = 'both', next_offset = vim.NIL,
  fields = { source = 'both', subject = 'plant', place = 'Kampen', exclude = '' },
  editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen', query_strategy = 2 })
key('i')
reply({ version = 1, files = { { name = 'photo.png', relative_path = 'photo.png', sha256 = 'hash' } } })
inputs[2].done('https://example.nl')
assert(requests[#requests].cmd[4] == 'ai-import')
reply(nil, 1, 'Ongeldige archieftag: https://example.nl.')
assert(menus[1].opts.native and menus[1].opts.prompt:find('Ongeldige archieftag', 1, true))
assert(menus[1].opts.prompt:find('tags blijven bewaard', 1, true))
menus[1].done('Opnieuw proberen')
reply({ version = 1, files = { { name = 'photo.png', relative_path = 'photo.png', sha256 = 'hash' } } })
assert(inputs[3].opts.default == 'https://example.nl', 'tags verloren na fout')
inputs[3].done('plant')
local latest = { '=== ARTIKEL ===', '', 'Mijn nieuwere kop', '', 'Eigen wijziging.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, latest)
reply({ version = 1, markdown = 'OUDE AI-TEKST', image_count = 1, batch_id = 'batch' })
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), latest), 'late import overschrijft redactiewerk')
assert(requests[#requests].cmd[4] ~= 'ai-import-finalize', 'stale import consumeert originelen')
vim.fn.delete(path)
print('pubble AI stock errors: OK')
