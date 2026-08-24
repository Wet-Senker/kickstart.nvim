package.loaded['agenda_page'] = nil

local module = require 'agenda_page'

local cmd = module._command 'prepare'
assert(cmd[1]:match '/%.venv/bin/python$')
assert(cmd[2] == '-m')
assert(cmd[3] == 'texttools.agenda_page_cli')
assert(cmd[4] == 'prepare')
assert(cmd[5] == nil)

local send_cmd = module._command('send', '/tmp/agenda.md', '--edition', 'SW')
assert(send_cmd[4] == 'send')
assert(send_cmd[5] == '/tmp/agenda.md')
assert(send_cmd[6] == '--edition')
assert(send_cmd[7] == 'SW')

local valid = module._decode_validation '{"valid":true,"errors":[],"edition":"B","days":2,"items":4}'
assert(valid.valid == true)
assert(valid.edition == 'B')
local valid_without_id = module._decode_validation '{"valid":true,"errors":[],"newspaper_article_id":null,"article_join_id":null}'
assert(valid_without_id.newspaper_article_id == nil, 'JSON-null werd aangezien voor een bestaand printconcept')
assert(valid_without_id.article_join_id == nil, 'JSON-null werd aangezien voor een bestaande article join')
assert(module._decode_validation 'geen json' == nil)

local buf = vim.api.nvim_create_buf(true, false)
module._replace_buffer(buf, 'regel 1\nregel 2\n')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
  'regel 1',
  'regel 2',
}))
assert(vim.bo[buf].filetype == 'markdown')
assert(vim.bo[buf].modified == true)
assert(module.is_prepared(buf) == false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== AGENDAPAGINA ===' })
assert(module.is_prepared(buf) == true)

module.setup()
assert(vim.fn.exists ':AgendaPagina' == 2)
local mapping = vim.fn.maparg('<leader>ka', 'n', false, true)
assert(type(mapping) == 'table' and mapping.desc == '[K]rant [A]gendapagina voorbereiden')

-- Verzenden vraagt precies één keer om de krant, valideert met die override
-- en geeft dezelfde code door aan de print-only CLI.
local original_select = vim.ui.select
local original_system = vim.system
local selection_count = 0
local sent = false
vim.ui.select = function(items, options, callback)
  selection_count = selection_count + 1
  assert(options.prompt == 'Agendapagina versturen naar welke krant?')
  callback(items[2]) -- De Swollenaer
end
vim.system = function(system_cmd, _, callback)
  if system_cmd[4] == 'validate' then
    assert(system_cmd[5] == '--edition' and system_cmd[6] == 'SW')
    callback {
      code = 0,
      stdout = '{"valid":true,"errors":[],"edition":"SW","days":1,"items":1,"newspaper_article_id":null,"article_join_id":null}',
    }
  elseif system_cmd[4] == 'send' then
    assert(system_cmd[6] == '--edition' and system_cmd[7] == 'SW')
    sent = true
    callback { code = 0, stdout = 'AGENDA_PAGE_RESULT_JSON:{"newspaper_article_id":106200}' }
  else
    error('onverwacht agenda-commando: ' .. table.concat(system_cmd, ' '))
  end
  return { is_closing = function() return false end }
end
local send_path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== AGENDAPAGINA ===' }, send_path)
local send_buf = vim.fn.bufadd(send_path)
vim.fn.bufload(send_buf)
module.send(send_buf)
assert(vim.wait(1000, function() return sent end), 'agenda-send werd niet bereikt')
assert(selection_count == 1, 'agenda-send vroeg meer dan eenmaal om een keuze')
vim.ui.select = original_select
vim.system = original_system
vim.fn.delete(send_path)

-- Het bestaande <leader>aw-pad moet een voorbereide agendapagina vóór de
-- gewone artikelpreflight naar de gespecialiseerde print-only send routeren.
local routed_buf
local original_send = module.send
module.send = function(target_buf) routed_buf = target_buf end
local route_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(route_buf, 0, -1, false, { '=== AGENDAPAGINA ===' })
require('ai_text').pubble_send(route_buf)
assert(routed_buf == route_buf)
module.send = original_send

print 'agenda page: OK'
