local photos = require 'pubble_photos'
local requests = {}
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  requests[#requests + 1] = { cmd = cmd, opts = opts, callback = callback }
  return {}
end
local function key(value, mode)
  local map = vim.fn.maparg(value, mode or 'n', false, true)
  assert(type(map.callback) == 'function', 'missing mapping: ' .. value)
  map.callback()
end
local function reply(data)
  data.version = 1
  requests[#requests].callback({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(50, function() return false end, 5)
end
local function input()
  assert(vim.wait(500, function()
    return vim.api.nvim_win_get_config(0).relative == 'editor'
  end, 5))
  return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
end
local article = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(article, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Artikeltekst.' })
vim.api.nvim_win_set_cursor(0, { 5, 3 })
local source_win = vim.api.nvim_get_current_win()
local tick = vim.api.nvim_buf_get_changedtick(article)
local before = vim.api.nvim_buf_get_lines(article, 0, -1, false)
photos.open()
reply({ query = 'zwolse milligerplas' })
local buf, win = input()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { 'zwolse milligerplas' }),
  'instructions must not be part of editable input')
assert(vim.b[buf].pubble_photo_source == article)
assert(vim.bo[buf].buftype == 'nofile' and not vim.bo[buf].swapfile)
assert(not vim.bo[buf].buflisted)
assert(#requests == 1, 'opening input must not search')
key('<Esc>', 'i')
assert(vim.api.nvim_win_is_valid(win), 'Escape must enter Normal, not cancel')
assert(vim.fn.maparg('<Esc>', 'n') == '')
-- Native motions/operators edit only the query, with ordinary Vim undo.
vim.cmd('normal! gg0dwiHonden ')
assert(vim.api.nvim_get_current_line() == 'Honden milligerplas')
-- End the synthetic Lua edit's undo block, as separate interactive edits do.
vim.cmd('normal! a' .. vim.api.nvim_replace_termcodes('<C-g>u<Esc>', true, false, true))
vim.cmd('normal! 0dw')
assert(vim.api.nvim_get_current_line() == 'milligerplas')
vim.cmd('normal! u')
assert(vim.api.nvim_get_current_line() == 'Honden milligerplas')
-- Calling the command from its own input focuses it, never treats it as article.
photos.open()
assert(vim.api.nvim_get_current_win() == win and #requests == 1)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'hond', '  milligerplas  ' })
key('<CR>')
assert(#requests == 2 and requests[2].cmd[4] == 'search')
assert(requests[2].cmd[6] == 'hond milligerplas', 'all query lines must be submitted')
assert(not vim.api.nvim_buf_is_valid(buf))
assert(vim.api.nvim_get_current_win() == source_win)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), { 5, 3 }))
assert(vim.api.nvim_buf_get_changedtick(article) == tick)
reply({ photos = {}, gallery_html = '', next_offset = 12 })
local picker = vim.api.nvim_get_current_buf()
assert(picker ~= article)
for _, k in ipairs({ '/', 'n', 'g', 'v' }) do
  assert(vim.fn.maparg(k, 'n') == '', 'native navigation must survive: ' .. k)
end
key('s'); buf, win = input()
assert(vim.api.nvim_get_current_line() == 'hond milligerplas')
key('<C-c>', 'i')
assert(not vim.api.nvim_win_is_valid(win))
assert(vim.api.nvim_get_current_buf() == picker and #requests == 2)
key(']p')
assert(#requests == 3 and requests[3].cmd[8] == '12')
reply({ photos = {}, gallery_html = '' })
key('s'); buf, win = input()
-- Changing the article during query editing cannot issue a stale search.
vim.api.nvim_buf_set_lines(article, -1, -1, false, { 'Eigen toevoeging.' })
key('<CR>')
assert(#requests == 3)
key('q')
assert(vim.api.nvim_get_current_win() == source_win)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), { 5, 3 }))
-- First-query cancellation, empty input and external :close do no searching.
for _, cancel in ipairs({ 'ctrl-c', 'empty', 'close' }) do
  photos.open(article)
  local count = #requests
  reply({ query = 'hond' })
  buf, win = input()
  if cancel == 'ctrl-c' then key('<C-c>')
  elseif cancel == 'empty' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '  ' }); key('<CR>')
  else vim.api.nvim_win_close(win, true) end
  assert(#requests == count)
  assert(vim.api.nvim_get_current_win() == source_win)
  assert(not vim.api.nvim_buf_is_valid(buf))
end
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(article, 0, #before, false), before))
-- Two windows on the same article: return to the window used, not the first match.
vim.cmd('vsplit')
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(second_win, { 3, 1 })
photos.open()
reply({ query = 'hond' })
input(); key('<C-c>')
assert(vim.api.nvim_get_current_win() == second_win)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(second_win), { 3, 1 }))
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(source_win), { 5, 3 }))
print('pubble photo Vim input: OK')
