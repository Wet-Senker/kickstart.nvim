local ai = require('ai_text')

local original_input = vim.ui.input
local original_system = vim.system
local original_notify = vim.notify
local command, options, notice

vim.ui.input = function(_, callback) callback('mijn artikel.txt') end
vim.system = function(cmd, opts, callback)
  command, options = cmd, opts
  callback({
    code = 0,
    stdout = vim.json.encode({
      schema_version = 1,
      text_path = vim.fn.expand('~/Desktop/mijn artikel.txt'),
      image_paths = { vim.fn.expand('~/Desktop/mijn artikel.jpg') },
    }),
    stderr = '',
  })
  return {}
end
vim.notify = function(message) notice = message end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'Tekst',
})
ai.export_designer_text(buf)

assert(vim.wait(1000, function() return notice ~= nil end, 10), 'exportcallback bleef hangen')
assert(command[2] == '-m' and command[3] == 'texttools.layout_designer_bundle_cli', 'gedeelde Python-actie ontbreekt')
assert(command[4] == vim.fn.expand('~/Desktop'), 'Bureaublad ontbreekt')
assert(command[5] == 'mijn artikel.txt', 'gekozen naam ontbreekt')
assert(command[6] == '--inbox' and type(command[7]) == 'string', 'Inboxpad ontbreekt')
assert(options.stdin:find('=== ARTIKEL ===', 1, true), 'buffersnapshot ontbreekt')
assert(notice:find('mijn artikel.txt', 1, true), 'resultaatnaam ontbreekt in melding')
assert(notice:find('+ foto', 1, true), 'foto ontbreekt in melding')

vim.ui.input = original_input
vim.system = original_system
vim.notify = original_notify
vim.api.nvim_buf_delete(buf, { force = true })
print('designer export: OK')
