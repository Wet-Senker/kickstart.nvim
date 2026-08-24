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
local valid_without_id = module._decode_validation '{"valid":true,"errors":[],"newspaper_article_id":null,"article_join_id":null,"pubble_url":null}'
assert(valid_without_id.newspaper_article_id == nil, 'JSON-null werd aangezien voor een bestaand printconcept')
assert(valid_without_id.article_join_id == nil, 'JSON-null werd aangezien voor een bestaande article join')
assert(valid_without_id.pubble_url == nil, 'JSON-null werd aangezien voor een gereed Pubbleconcept')
local ready = module._decode_validation '{"valid":true,"newspaper_article_id":106200,"pubble_url":"https://brugmedia.pubble.dev/articles/newspaper/106200"}'
assert(ready.pubble_url:match '/articles/newspaper/106200$')
assert(
  module._duplicate_candidate_line {
    first_date = 'dinsdag 25 augustus',
    first_title = 'Orgelconcert',
    second_title = 'Orgelconcert Buitenkerk',
    reason = 'titels lijken sterk op elkaar',
    score = 91,
  } == 'dinsdag 25 augustus: Orgelconcert ↔ Orgelconcert Buitenkerk (titels lijken sterk op elkaar, 91%)'
)
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

-- Sterke doublurekandidaten vragen een tweede, bewuste bevestiging en geven
-- die keuze expliciet door aan de CLI.
local duplicate_selection_count = 0
local duplicate_sent = false
vim.ui.select = function(items, options, callback)
  duplicate_selection_count = duplicate_selection_count + 1
  if options.prompt == 'Agendapagina versturen naar welke krant?' then
    callback(items[1])
    return
  end
  assert(options.prompt == 'Zijn deze overeenkomsten gecontroleerd?')
  assert(items[1].label == 'Annuleren' and items[2].label == 'Toch verzenden')
  callback(items[2])
end
vim.system = function(system_cmd, _, callback)
  if system_cmd[4] == 'validate' then
    callback {
      code = 0,
      stdout = vim.json.encode {
        valid = true,
        errors = {},
        edition = 'B',
        days = 1,
        items = 2,
        duplicate_candidates = {
          {
            first_date = 'dinsdag 25 augustus',
            first_title = 'Orgelconcert',
            second_title = 'Orgelconcert Buitenkerk',
            reason = 'titel en tekst lijken sterk op elkaar',
            score = 90,
          },
        },
      },
    }
  elseif system_cmd[4] == 'send' then
    assert(system_cmd[8] == '--allow-duplicates')
    duplicate_sent = true
    callback {
      code = 0,
      stdout = 'AGENDA_PAGE_RESULT_JSON:{"newspaper_article_id":106201,"article_url":"https://brugmedia.pubble.dev/articles/newspaper/106201"}',
    }
  else
    error('onverwacht agenda-commando: ' .. table.concat(system_cmd, ' '))
  end
  return { is_closing = function() return false end }
end
local duplicate_path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== AGENDAPAGINA ===' }, duplicate_path)
local duplicate_buf = vim.fn.bufadd(duplicate_path)
vim.fn.bufload(duplicate_buf)
module.send(duplicate_buf)
assert(vim.wait(1000, function() return duplicate_sent end), 'bevestigde doublure-send werd niet bereikt')
assert(duplicate_selection_count == 2, 'doublurecontrole vroeg niet exact één extra bevestiging')
vim.ui.select = original_select
vim.system = original_system
vim.fn.delete(duplicate_path)

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
