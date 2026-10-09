local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local requests, messages = {}, {}
vim.notify = function(message) table.insert(messages, message) end
vim.system = function(cmd, opts, callback)
  table.insert(requests, { cmd = cmd, opts = opts, callback = callback })
  return {}
end
dialog.input = function(opts, callback)
  assert(opts.vim_edit == true, 'fotozoekinvoer moet Vim-bewerking ondersteunen')
  callback(opts.default)
end
dialog.confirm = function() return 1 end
local function reply(index, data, code)
  data.version = data.version or 1
  requests[index].callback({ code = code or 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(100, function() return false end, 10)
end
local function article()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
  return buf
end
local candidate = { image_metadata_id = 731, source_article_id = 912,
  source_title = 'Bronartikel', edition = 'B', date = '2026-10-01',
  preview_url = 'https://images.pubble.cloud/photo.jpg', caption = 'Bijschrift\nmet tweede regel', credit = 'Fotograaf' }
local data = { version = 1, photos = { candidate }, gallery_html = '<html>metadata only</html>',
  excluded_articles = 3, unclassified_articles = 1 }
local function mapping(buf, key)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == key then return map.callback end
  end
  error('mapping ontbreekt: ' .. key)
end

-- Changing the source while suggesting a query must not start a stale search.
local a = article()
photos.open(a)
assert(requests[1].cmd[4] == 'suggest')
vim.api.nvim_buf_set_lines(a, -1, -1, false, { 'Eigen wijziging.' })
reply(1, { query = 'Bovenkerk' })
assert(#requests == 1)
assert(table.concat(vim.api.nvim_buf_get_lines(a, 0, -1, false)):find('Eigen wijziging', 1, true))

-- Search, preview and select use only the shared JSON actions. No auto-send.
photos.open(a)
reply(2, { query = 'Bovenkerk' })
assert(requests[3].cmd[4] == 'search')
reply(3, data)
local picker = vim.api.nvim_get_current_buf()
assert(picker ~= a)
local display = table.concat(vim.api.nvim_buf_get_lines(picker, 0, -1, false), '\n')
assert(display:find('Controleer context en gebruiksrechten', 1, true))
assert(not display:find('112 uitgesloten', 1, true))
for _, key in ipairs({ '/', 'n', 'g', 'v' }) do
  assert(vim.fn.maparg(key, 'n', false, true).buffer ~= 1, 'Vim-toets overschreven: ' .. key)
end
vim.api.nvim_win_set_cursor(0, { 5, 0 })
assert(vim.fn.maparg('o', 'n') == '')
mapping(picker, '<CR>')()
assert(requests[4].cmd[4] == 'select')
local payload = vim.json.decode(requests[4].opts.stdin)
assert(payload.photo.image_metadata_id == 731)
-- A late apply callback never overwrites newer edits either.
vim.api.nvim_buf_set_lines(a, -1, -1, false, { 'Nog een wijziging.' })
reply(4, { markdown = 'VEROUDERD' })
assert(vim.api.nvim_buf_get_lines(a, -2, -1, false)[1] == 'Nog een wijziging.')

-- Closing a picker cancels its late callbacks without changing the article.
photos.open(a)
reply(5, { query = 'Bovenkerk' })
reply(6, data)
picker = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 5, 0 })
mapping(picker, '<CR>')()
mapping(picker, 'q')()
reply(7, { markdown = 'OOK VEROUDERD' })
assert(vim.api.nvim_buf_get_lines(a, -2, -1, false)[1] == 'Nog een wijziging.')

-- Successful selection ends in the source buffer, ready for review, not send.
photos.open(a)
reply(8, { query = 'Bovenkerk' })
reply(9, data)
picker = vim.api.nvim_get_current_buf()
vim.api.nvim_win_set_cursor(0, { 5, 0 })
mapping(picker, '<CR>')()
reply(10, { markdown = 'b: Bijschrift\nc: Fotograaf\n\n=== ARTIKEL ===\n\nKop\n' })
assert(vim.api.nvim_get_current_buf() == a)
assert(vim.api.nvim_buf_get_lines(a, 0, 1, false)[1] == 'b: Bijschrift')
assert(#requests == 10, 'selection must not publish automatically')
photos.setup()
assert(vim.fn.exists(':PubbleFoto') == 2)
assert(vim.fn.maparg('<leader>pf', 'n') ~= '')
print('pubble photos: OK')
