local previous_root = vim.env.TEXTTOOLS_ROOT
vim.env.TEXTTOOLS_ROOT = '/tmp/andere texttools'
package.loaded['texttools_commands'] = nil

local commands = require('texttools_commands')

assert(commands.root() == '/tmp/andere texttools')
assert(commands.path('nvim', 'mail.applescript') == '/tmp/andere texttools/nvim/mail.applescript')
assert(commands.bin('aitext') == '/tmp/andere texttools/.venv/bin/aitext')

vim.env.TEXTTOOLS_ROOT = previous_root
print('texttools commands: OK')
