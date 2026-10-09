local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local browser = require 'ordered_browser'

local requests, opened = {}, {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  requests[#requests + 1] = { cmd = cmd, opts = opts, callback = callback }
  return {}
end
dialog.input = function(opts, done) done(opts.default) end
browser.open_urls = function(urls)
  opened[#opened + 1] = urls[1]
  return true
end

local function reply(data)
  data.version = data.version or 1
  requests[#requests].callback({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end

local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(map.callback) == 'function', 'mapping ontbreekt: ' .. lhs)
  map.callback()
end

local path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' }, path)
vim.cmd('edit ' .. vim.fn.fnameescape(path))
local source = vim.api.nvim_get_current_buf()
photos.open(source)
reply({ editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen' })
reply({
  photos = {}, candidates = {}, source = 'both', next_offset = vim.NIL,
  fields = { source = 'both', subject = 'plant', place = 'Kampen', exclude = '' },
  editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen', query_strategy = 2,
})

key('a')
assert(requests[#requests].cmd[4] == 'ai-prompt')
assert(requests[#requests].opts.stdin:find('Kop', 1, true))
reply({ prompt = 'VEILIGE STOCKPROMPT', chatgpt_url = 'https://chatgpt.com/' })
assert(vim.fn.getreg('"') == 'VEILIGE STOCKPROMPT')
assert(opened[#opened] == 'https://chatgpt.com/')

key('i')
assert(requests[#requests].cmd[4] == 'ai-import')
local payload = vim.json.decode(requests[#requests].opts.stdin)
assert(vim.fn.resolve(vim.fn.fnamemodify(payload.article_path, ':p'))
  == vim.fn.resolve(vim.fn.fnamemodify(path, ':p')), payload.article_path .. ' ~= ' .. path)
assert(payload.form_text:find('Archieftags:', 1, true))
reply({
  markdown = '---\nmedia:\n  stock_image:\n    filename: ai-stock.png\n    library_location_id: 24\n---\n\nb: Illustratief beeld\nc: AI-gegenereerd beeld (OpenAI)\n\n=== ARTIKEL ===\n\nKop\n\nTekst.\n',
  keywords = { 'plant', 'aarde', 'natuur' }, stock_location_id = 24,
})
assert(vim.api.nvim_get_current_buf() == source)
local result = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n')
assert(result:find('library_location_id: 24', 1, true))
assert(result:find('AI%-gegenereerd beeld'))

vim.fn.delete(path)
print('pubble AI stock: OK')
