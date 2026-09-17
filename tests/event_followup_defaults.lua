local ai = require('ai_text')

local original_system = vim.system
local original_select = vim.ui.select
local dialogs = {}
local prepare_calls = 0

vim.system = function(command, _, callback)
  prepare_calls = prepare_calls + 1
  assert(command[2] == 'voorbereiden', 'onverwacht vervolgsubproces gestart')
  callback {
    code = 0,
    stdout = vim.json.encode {
      beschikbaar = true,
      kort = { mogelijk = true, datum = '2099-08-18' },
      reminder = {
        mogelijk = true,
        dagen = { '2099-08-28', '2099-08-29' },
      },
    },
    stderr = '',
  }
  return {}
end

vim.ui.select = function(items, options, callback)
  table.insert(dialogs, { items = vim.deepcopy(items), options = options })
  callback(items[1])
end

local file = vim.fn.tempname() .. '.md'
vim.fn.writefile({ 'Kop', '', 'Tekst.' }, file)
local buf = vim.api.nvim_create_buf(false, true)
local finished
ai._event_prepare(buf, file, {}, { 'B' }, function(ok, err, prepared)
  finished = { ok = ok, err = err, prepared = prepared }
end)

assert(vim.wait(1000, function() return finished ~= nil end, 20), 'vervolgvragen werden niet afgerond')
assert(prepare_calls == 1, 'Nee/Nee startte toch tekstgeneratie')
assert(#dialogs == 2, 'niet beide vervolgvragen zijn gesteld')
for _, dialog in ipairs(dialogs) do
  assert(dialog.items[1] == 'Nee', 'Nee is niet de eerste keuze')
  assert(dialog.items[2] == 'Ja', 'Ja is niet de tweede keuze')
  assert(dialog.options.default == 1, 'Nee is niet als startkeuze gemarkeerd')
end
assert(dialogs[1].options.prompt:find('Korte versie', 1, true), 'eerste vraag gaat niet over de korte versie')
assert(dialogs[2].options.prompt:find('Dagreminder', 1, true), 'tweede vraag gaat niet over de dagreminder')
assert(finished.ok and finished.err == nil and finished.prepared == false, 'Nee/Nee ging niet gewoon verder')

vim.fn.delete(file)
vim.api.nvim_buf_delete(buf, { force = true })
vim.system = original_system
vim.ui.select = original_select

print('event followup defaults: OK')
