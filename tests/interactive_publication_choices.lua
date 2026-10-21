local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, 'p')
vim.env.TEXTTOOLS_INBOX_DIR = temporary
local ai = require('ai_text')
local dialog = require('user_dialog')
local source = vim.api.nvim_get_current_buf()
local imported = {
  'Kop', '', 'KAMPEN - De gemeente presenteert een uitgebreid plan voor de binnenstad.', '',
  'Bewoners kunnen reageren op nieuwe bomen, bredere stoepen en ruimte voor fietsers.', '',
  'Eerst worden kabels en leidingen vervangen. Daarna volgen bestrating en nieuwe groenstroken.',
}
vim.api.nvim_buf_set_lines(source, 0, -1, false, imported)
ai._capture_import_baseline(source)
local native_uis, native_confirm = vim.api.nvim_list_uis, vim.fn.confirm
vim.api.nvim_list_uis = function() return { {} } end
vim.fn.confirm = function() error('publicatievraag verscheen onderaan') end
local calls = 0
vim.system = function() calls = calls + 1; error('verzending begon vóór een geldige keuze') end
vim.cmd('PubbleSend')
assert(vim.wait(1000, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
assert(calls == 0)
vim.cmd('PubbleSend') -- Ook de commandoroute mag geen tweede actie beginnen.
assert(calls == 0)
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Een nieuw feit tijdens de keuze.' })
vim.fn.maparg('1', 'n', false, true).callback()
assert(calls == 0 and not vim.b[source].send_safeguard_approved_body,
  'veranderde bron kreeg publicatietoestemming')

-- Ook een destructieve reset mag na een late keuze geen externe write starten.
require('pubble_reset').setup()
local pending
vim.system = function(command, _, done)
  calls = calls + 1
  assert(command[4] == 'plan', 'reset begon al met toepassen')
  pending = done
  return {}
end
vim.cmd('PubbleReset')
assert(calls == 1 and pending)
pending({ code = 0, stdout = vim.json.encode({ snapshot_status = 'available',
  items = { { action = 'offline', label = 'Webartikel', object_id = 123 } } }) })
assert(vim.wait(1000, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere eigen tekst vóór reset.' })
vim.fn.maparg('1', 'n', false, true).callback()
assert(calls == 1, 'late resetkeuze startte een externe mutatie')
assert(vim.api.nvim_buf_get_lines(source, -2, -1, false)[1] == 'Nieuwere eigen tekst vóór reset.')
vim.api.nvim_list_uis, vim.fn.confirm = native_uis, native_confirm
vim.fn.delete(temporary, 'rf')
print('interactive publication choices: OK')
