local ai = require('ai_text')
local dialog = require('user_dialog')
local source = vim.api.nvim_get_current_buf()
local original = { '=== ARTIKEL ===', '', 'Kop', '', 'Mijn artikel.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, original)
local killed, callback = 0
vim.system = function(command, _, done)
  assert(command[2] == 'tekstcheck', 'test startte onverwacht ander werk')
  callback = done
  return {
    is_closing = function() return false end,
    kill = function(_, signal) assert(signal == 'sigterm'); killed = killed + 1 end,
  }
end
ai.tekstcheck()
assert(callback and vim.b[source].pending_jobs == 1)
local answers = 0
dialog.input({ prompt = 'Naam', default = 'Eigen invoer', source_buf = source }, function() answers = answers + 1 end)
assert(vim.wait(1000, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
local input_win = vim.api.nvim_get_current_win()
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(vim.fn.maparg('<Esc>', 'n') == '<Nop>', 'herhaalde Escape is niet onschadelijk')
assert(killed == 0 and answers == 0 and vim.api.nvim_win_is_valid(input_win),
  'Escape stopte actief werk of annuleerde een invoervervolg')
assert(vim.b[source].pending_jobs == 1, 'Escape meldde actief werk ten onrechte gereed')
vim.fn.maparg('<C-c>', 'n', false, true).callback()
assert(answers == 1 and killed == 0, 'invoer sluiten stopte een onafhankelijke AI-taak')
assert(ai.cancel_ai(source) and killed == 1, 'expliciete AI-annulering werkt niet meer')
callback({ code = 0, signal = 0, stdout = 'LAAT RESULTAAT', stderr = '' })
assert(vim.wait(1000, function() return vim.b[source].pending_jobs == 0 end))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), original),
  'expliciet geannuleerde AI paste alsnog een laat resultaat toe')
print('Escape and active jobs: OK')
