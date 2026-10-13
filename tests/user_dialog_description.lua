local dialog = require('user_dialog')
local input, result
local before = #vim.api.nvim_list_wins()
dialog.input({ prompt = 'Alleen tags', description = 'Foto 1: plant.png\nFoto 2: aarde.png\nDeze lijst is alleen ter controle.',
  default = 'plant, aarde, natuur', vim_edit = true, footer = ' Enter: importeren ',
  on_open = function(buf) input = buf end }, function(value) result = value end)
assert(vim.wait(1000, function() return input ~= nil end, 5))
assert(#vim.api.nvim_list_wins() == before + 2)
assert(table.concat(vim.api.nvim_buf_get_lines(input, 0, -1, false), '\n') == 'plant, aarde, natuur')
local readonly
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  if buf ~= input and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('plant.png', 1, true) then readonly = buf end
end
assert(readonly and not vim.bo[readonly].modifiable, 'bestandsnamen zijn niet read-only')
local map = vim.fn.maparg('<CR>', 'n', false, true)
assert(type(map.callback) == 'function')
map.callback()
assert(result == 'plant, aarde, natuur', 'bestandscontext belandt in tags')
assert(#vim.api.nvim_list_wins() == before and not vim.api.nvim_buf_is_valid(readonly), 'contextvenster blijft achter')
print('user dialog description: OK')
