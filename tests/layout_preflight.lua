local ai_text = require('ai_text')
local layout_export = require('layout_export')

local tmp = vim.fn.tempname()
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'Kop {{naam}}',
  '',
  'Tekst.',
})
assert(layout_export.prepare(buf, { dir = tmp, txt_name = 'test.txt' }))

local original_notify = vim.notify
local original_system = vim.system
local notice
vim.notify = function(message) notice = message end
vim.system = function() error('externe actie gestart vóór placeholdercontrole') end

local ok, error_message = pcall(ai_text.pubble_send, buf)

vim.notify = original_notify
vim.system = original_system
assert(ok, error_message)
assert(notice and notice:find('{{naam}}', 1, true), 'placeholderfout is niet aan de gebruiker gemeld')
assert(vim.fn.filereadable(tmp .. '/test.txt') == 0, 'preflight schreef al een vormgevingstekst')
assert(layout_export.pending(buf), 'exportplan verdween na geweigerde preflight')

local no_export_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(no_export_buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'Ook een template zonder vormgeving {{veld}} moet blokkeren.',
})
local valid = layout_export.validate(no_export_buf)
assert(not valid, 'placeholder zonder vormgevingsplan werd niet geweigerd')

vim.fn.delete(tmp, 'rf')
print('layout preflight: OK')
