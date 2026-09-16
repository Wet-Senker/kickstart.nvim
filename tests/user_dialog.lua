local dialog = require('user_dialog')
local function shown()
  assert(vim.wait(500, function()
    return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == 'editor'
  end, 5), 'overlay ontbreekt')
end
local function key(value)
  local mapping = vim.fn.maparg(value, 'n', false, true)
  assert(type(mapping.callback) == 'function', 'toets ontbreekt: ' .. value)
  mapping.callback()
end
local choice, calls = nil, 0
dialog.select({ 'Ja', 'Nee' }, { prompt = 'Import', required = true, default = 2 }, function(item)
  choice = item; calls = calls + 1
end)
shown()
key('<Esc>')
assert(calls == 0, 'Escape beantwoordde verplichte vraag')
key('<C-c>')
assert(calls == 0, 'Ctrl-C beantwoordde verplichte vraag')
key('<CR>')
assert(choice == 'Nee' and calls == 1, 'expliciet antwoord ontbreekt')

dialog.select({ 'A' }, { prompt = 'Handmatig' }, function(item) choice = item; calls = calls + 1 end)
shown(); key('<Esc>')
assert(choice == nil and calls == 2, 'handmatig menu niet geannuleerd')

dialog.select({ 'A' }, { prompt = 'Eerste' }, function(item) choice = item end)
dialog.select({ 'B' }, { prompt = 'Tweede' }, function(item) choice = item end)
shown(); key('<CR>'); shown(); key('<CR>')
assert(choice == 'B', 'wachtrij verloor vraag')

dialog.select({ 'Blijft staan' }, { prompt = 'Import', required = true }, function(item) choice = item end)
shown()
vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
shown(); key('<CR>')
assert(choice == 'Blijft staan', 'extern sluiten verloor verplichte vraag')

dialog.input({ prompt = 'Naam', default = 'Nick' }, function(item) choice = item end)
shown(); vim.cmd('stopinsert'); key('<CR>')
assert(choice == 'Nick', 'invoer verloren')
dialog.input({ prompt = 'Naam' }, function(item) choice = item end)
shown(); vim.cmd('stopinsert'); key('<Esc>')
assert(choice == nil, 'invoer niet geannuleerd')

-- Ja/nee-vragen gaan native via vim.fn.confirm: geen overlay, geen vim.wait-lus,
-- dus ze kunnen niet vastlopen in het verse-import-venster.
local original_confirm_native = vim.fn.confirm
vim.fn.confirm = function() return 2 end
assert(dialog.confirm('Vraag', '&Ja\n&Nee', 1) == 2, 'native ja/nee-vraag mislukt')
-- Een verplichte vraag negeert Escape (0) en stelt zich opnieuw tot er een echt
-- antwoord is.
local answers, calls = { 0, 0, 1 }, 0
vim.fn.confirm = function() calls = calls + 1; return table.remove(answers, 1) end
assert(dialog.confirm('Verplicht?', '&Ja', 1, true) == 1 and calls == 3,
  'verplichte vraag niet opnieuw gesteld bij Escape')
vim.fn.confirm = original_confirm_native
-- Import policies are explicit; hand-triggered rewrite questions allow Escape.
local ai = require('ai_text')
local original_confirm = dialog.confirm
local original_select = dialog.select
local required
dialog.confirm = function(_, _, _, policy) required = policy; return 2 end
ai._calendar_date_confirm(5); assert(required == true, 'agendavraag niet verplicht')
ai._112_confirm('112'); assert(required == true, '112-vraag niet verplicht')
ai._rubric_confirm({ candidates = {} }); assert(required == true, 'rubriekvraag niet verplicht')
ai._rubriek_confirm_simple('Sport'); assert(required == true, 'sportvraag niet verplicht')
dialog.select = function(_, opts, done)
  required = opts.required
  done(nil, nil)
end
ai._edition_mode_choice_async({ 'B', 'SW' }, { 'Brug', 'Swollenaer' }, nil, function() end)
assert(required ~= true, 'handmatige rewritevraag niet annuleerbaar of niet asynchroon')
dialog.confirm = original_confirm
dialog.select = original_select
print('user dialog: OK')
