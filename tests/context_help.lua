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

local phase = 'Eerste fase'
help.register(buf, function()
  return {
    title = 'Dynamische hulp',
    status = phase,
    sections = {
      { heading = 'Nu doen', lines = { 'Voer de volgende stap uit.' } },
    },
  }
end)
local first_dynamic = help._resolve_entry(buf)
assert(first_dynamic.status == 'Eerste fase', 'provider werd niet actueel uitgelezen')
phase = 'Tweede fase'
local second_dynamic = help._resolve_entry(buf)
assert(second_dynamic.status == 'Tweede fase', 'provideruitkomst bleef statisch gecachet')
local rendered = table.concat(help._help_lines(second_dynamic), '\n')
assert(rendered:find('Status\n  Tweede fase', 1, true), 'statusblok ontbreekt')
assert(rendered:find('Nu doen\n  Voer de volgende stap uit.', 1, true), 'sectie ontbreekt')

local cleanup_count = 0
for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = 'BufWipeout', buffer = buf }) do
  if autocmd.callback then cleanup_count = cleanup_count + 1 end
end
help.register(buf, function() return { title = 'Nogmaals', lines = {} } end)
local cleanup_after = 0
for _, autocmd in ipairs(vim.api.nvim_get_autocmds { event = 'BufWipeout', buffer = buf }) do
  if autocmd.callback then cleanup_after = cleanup_after + 1 end
end
assert(cleanup_after == cleanup_count, 'herregistratie stapelde cleanup-autocmds')

print 'context help: OK'
