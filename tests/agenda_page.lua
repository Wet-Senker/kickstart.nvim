package.loaded['agenda_page'] = nil

local module = require 'agenda_page'

local cmd = module._command('prepare', '--edition', 'B')
assert(cmd[1]:match '/%.venv/bin/python$')
assert(cmd[2] == '-m')
assert(cmd[3] == 'texttools.agenda_page_cli')
assert(cmd[4] == 'prepare')
assert(cmd[5] == '--edition')
assert(cmd[6] == 'B')

local valid = module._decode_validation '{"valid":true,"errors":[],"edition":"B","days":2,"items":4}'
assert(valid.valid == true)
assert(valid.edition == 'B')
assert(module._decode_validation 'geen json' == nil)

local buf = vim.api.nvim_create_buf(true, false)
module._replace_buffer(buf, 'regel 1\nregel 2\n')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
  'regel 1',
  'regel 2',
}))
assert(vim.bo[buf].filetype == 'markdown')
assert(vim.bo[buf].modified == true)

module.setup()
assert(vim.fn.exists ':AgendaPagina' == 2)
local mapping = vim.fn.maparg('<leader>ka', 'n', false, true)
assert(type(mapping) == 'table' and mapping.desc == '[K]rant [A]gendapagina')

print 'agenda page: OK'
