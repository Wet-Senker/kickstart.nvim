local help = require 'context_help'
help.setup()

local buf = vim.api.nvim_create_buf(false, true)
help.register(buf, {
  title = 'Testscherm',
  lines = { 'Eerste regel', 'Tweede regel' },
})

local mapping = vim.fn.maparg('<leader>kh', 'n', false, true)
assert(type(mapping) == 'table' and mapping.desc == '[K]rant contextuele [h]ulp', 'globale contexthelpmapping ontbreekt')

vim.api.nvim_set_current_buf(buf)
local help_buf, win = help.show(buf)
assert(vim.api.nvim_win_is_valid(win), 'contexthelpvenster ontbreekt')
local text = table.concat(vim.api.nvim_buf_get_lines(help_buf, 0, -1, false), '\n')
assert(text:find('Testscherm', 1, true), 'contexttitel ontbreekt')
assert(text:find('Eerste regel', 1, true), 'contextregels ontbreken')
vim.api.nvim_win_close(win, true)

print 'context help: OK'
