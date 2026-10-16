local dialog = require 'user_dialog'
local source = vim.api.nvim_get_current_buf()
local function flush() vim.wait(30, function() return false end, 5) end
local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true); assert(type(map.callback) == 'function', lhs); map.callback(); flush()
end
local first, photo, last
dialog.input({ prompt = 'Andere bewerking', default = 'eerste', vim_edit = true }, function(value) first = value end)
flush()
local original_window = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'Mijn nog niet bevestigde invoer' })
dialog.input({ prompt = 'Wachtende bewerking', default = 'laatste', vim_edit = true }, function(value) last = value end)
dialog.input({ prompt = 'Foto zoeken', default = 'biljart', vim_edit = true, priority = true,
  source_buf = source }, function(value) photo = value end)
flush()
assert(not vim.api.nvim_win_is_valid(original_window), 'oude dialoog is niet gepauzeerd')
assert(vim.api.nvim_get_current_line() == 'biljart', 'fotozoekvraag kreeg geen voorrang')
assert(vim.b[0].user_dialog_source == source, 'origineel artikel niet bewaard')
assert(first == nil and last == nil, 'pauzeren mag geen vraag beantwoorden')
key('<CR>')
assert(photo == 'biljart')
assert(vim.api.nvim_get_current_line() == 'Mijn nog niet bevestigde invoer', 'invoerdraft verloren')
key('<CR>')
assert(first == 'Mijn nog niet bevestigde invoer')
assert(vim.api.nvim_get_current_line() == 'laatste', 'wachtrij is verstoord')
key('<CR>')
assert(last == 'laatste')
print('user dialog priority: OK')
