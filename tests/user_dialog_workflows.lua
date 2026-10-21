local dialog = require('user_dialog')
local notify = require('texttools_notify')
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
local native_uis, native_confirm = vim.api.nvim_list_uis, vim.fn.confirm
vim.api.nvim_list_uis = function() return { {} } end
vim.fn.confirm = function() error('interactieve actie gebruikte de prompt onderaan') end
local function shown()
  assert(vim.wait(1000, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
end
local function key(lhs) vim.fn.maparg(lhs, 'n', false, true).callback() end
local stage, choice = 0
local unsafe_calls = 0
dialog.command('TestUnsafeWhileQuestion', function() unsafe_calls = unsafe_calls + 1 end, {})
local native_wait = vim.wait
vim.wait = function() error('een keuze blokkeerde de editor') end
dialog.run(function()
  stage = 1
  choice = dialog.confirm('Doorgaan?', '&Ja\n&Nee', 2, true)
  stage = 2
end)
vim.wait = native_wait
assert(stage == 1, 'actie wachtte niet op expliciet antwoord')
shown()
vim.cmd('TestUnsafeWhileQuestion')
assert(unsafe_calls == 0, 'andere actie begon op de keuzebuffer in plaats van het artikel')
key('<Esc>')
assert(stage == 1, 'Escape beantwoordde verplichte vraag')
local responsive = false
vim.defer_fn(function() responsive = true end, 1)
assert(vim.wait(1000, function() return responsive end), 'editor stond stil tijdens een vraag')
dialog.resume(); shown(); key('<CR>')
assert(stage == 2 and choice == 2, 'hervatting verloor het gekozen antwoord')

-- Callback-context blijft bij de bron, ook als een ander artikel actief is.
local callback = notify.bind(source, function()
  assert(dialog.confirm('Foto gebruiken?', '&Ja\n&Nee', 1) == 0,
    'gewijzigde bron kreeg alsnog toestemming')
  stage = 3
end)
callback(); shown()
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Mijn nieuwere tekst.' })
key('<CR>')
assert(stage == 3, 'asynchrone callback werd niet afgerond')

-- Registratie-adapters en inputlist gebruiken hetzelfde oppervlak.
dialog.keymap('n', '<F12>', function()
  choice = dialog.inputlist({ 'Persoon kiezen', '1. Eerste', '2. Tweede' })
end, {})
vim.fn.maparg('<F12>', 'n', false, true).callback()
vim.fn.maparg('<F12>', 'n', false, true).callback() -- geen tweede vraag
shown()
local labels = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(labels:find('1. Eerste', 1, true) and not labels:find('1. 1.', 1, true), 'oude inputlist kreeg dubbele nummers')
key('2')
assert(choice == 2)
vim.wait(20, function() return false end)
assert(vim.api.nvim_win_get_config(0).relative ~= 'editor', 'dubbel indienen liet een tweede vraag achter')
dialog.command('TestWorkflowQuestion', function()
  choice = dialog.confirm('Laatste vraag', '&Ja\n&Nee', 1)
end, {})
vim.cmd('TestWorkflowQuestion'); shown(); key('<Esc>')
assert(choice == 0, 'handmatige vraag werd niet geannuleerd')
vim.api.nvim_list_uis, vim.fn.confirm = native_uis, native_confirm
print('user dialog workflows: OK')
