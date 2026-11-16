local exporter = require('article_export')
local original_system = vim.system
local original_notify = vim.notify
local original_setreg = vim.fn.setreg
local calls, notices, clipboard = {}, {}, nil

vim.notify = function(message) table.insert(notices, message) end
vim.fn.setreg = function(register, value)
  assert(register == '+')
  clipboard = value
end
vim.system = function(command, options, done)
  table.insert(calls, { command = command, options = options })
  local result
  if command[3] == 'texttools.article_export_cli' then
    assert(options.stdin:find('=== ARTIKEL ===', 1, true), 'buffersnapshot ontbreekt')
    result = { code = 0, stdout = vim.json.encode {
      schema_version = 1,
      markdown = '**Fotocredit:** Maker\n\nKop\n\nTekst\n',
    }, stderr = '' }
  else
    assert(command[1] == '/bin/zsh' and command[5]:find('pandoc', 1, true),
      'rich-textadapter ontbreekt')
    assert(options.stdin:find('Fotocredit', 1, true), 'rich text kreeg niet de schone uitvoer')
    result = { code = 0, stdout = '', stderr = '' }
  end
  vim.schedule(function() done(result) end)
  return {}
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B', 'c: Maker', '', '=== ARTIKEL ===', '', 'Kop', '', 'Tekst',
})

exporter.copy_markdown(buf)
assert(vim.wait(1000, function() return clipboard ~= nil end, 10), 'Markdownkopie bleef hangen')
assert(clipboard:find('Fotocredit', 1, true), 'schone Markdown ontbreekt')

exporter.copy_rich_text(buf)
assert(vim.wait(1000, function() return #calls == 3 end, 10), 'rich-textkopie bleef hangen')
assert(notices[#notices]:find('rich text', 1, true), 'succesmelding ontbreekt')

vim.system = original_system
vim.notify = original_notify
vim.fn.setreg = original_setreg
vim.api.nvim_buf_delete(buf, { force = true })
print('article export: OK')
