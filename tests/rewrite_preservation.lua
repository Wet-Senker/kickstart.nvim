package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

-- Deze regressie toetst expliciet de intact gehouden terugvalroute.
vim.env.TEXTTOOLS_WRITING_PROFILE = 'behoudplan-20261021'

local ai = require 'ai_text'
local dialog = require 'user_dialog'
local original_system = vim.system
local original_post = ai._post_full_article_rewrite
local requested, callback, post
local original_select = dialog.select
dialog.select = function() error('één editie toonde een extra redactie-menu') end
local body = 'Bronkop\n\nKAMPEN - Jan Jansen brengt een album uit.\n\n'
  .. 'Deze bronalinea blijft precies zo.\nDeze regel hoort bij dezelfde alinea.'
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function wait(f) assert(vim.wait(2000, f, 10), 'behoudsflow bleef hangen') end
local function drain()
  local done = false
  vim.schedule(function() done = true end)
  wait(function() return done end)
end
local function setup()
  requested, callback, post = nil, nil, nil
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split('e: B\nFoto: Anne Tester\n\n=== ARTIKEL ===\n\n' .. body, '\n'))
  ai._mark_duplicate_check_done(buf)
  ai._post_full_article_rewrite = function(options) post = options end
  vim.system = function(command, opts, done)
    if command[2] == 'krantversie' then
      requested = { command = command, stdin = opts.stdin }
      callback = done
      return { kill = function() end }
    end
    assert(command[1] ~= 'bash', 'behoud startte de volledige AI/Kampen-pipeline')
    if not done or command[2] == 'inspect' then return original_system(command, opts, done) end
    done { code = 0, stdout = '{"editions":["B"],"has_explicit_editions":true,"detection":{"confidence":"none","editions":[]}}', stderr = '' }
    return { kill = function() end }
  end
  ai.rewrite_article_buffer()
  wait(function() return callback ~= nil end)
  assert(vim.tbl_contains(requested.command, '--edit-mode') and vim.tbl_contains(requested.command, 'auto'))
  return buf
end

local buf = setup()
local before = text(buf)
callback { code = 1, stdout = '', stderr = 'Ongeldig bodybehoudplan' }
drain()
assert(text(buf) == before and post == nil, 'mislukt plan werd toch toegepast')
vim.api.nvim_buf_delete(buf, { force = true })

buf = setup()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwe body tijdens AI.' })
callback { code = 0, stdout = body, stderr = '' }
drain()
assert(text(buf):find('Nieuwe body tijdens AI.', 1, true) and post == nil, 'late AI overschreef nieuwere body')
vim.api.nvim_buf_delete(buf, { force = true })

-- Echte Python-parser/schema/applicatie/CLI onder een mock van alleen de AI.
buf = setup()
assert(requested.stdin == body, 'controls/foto gingen naar AI')
local stub = [=[
import json
from unittest.mock import patch
from texttools.ai_cli import main
from texttools.article_preservation import PreservationSource
def fake(**kw):
    data = json.loads(kw['text'])
    assert kw['output_format']['format']['name'] == 'article_edit_plan_v1'
    assert 'De Brug' in kw['instructions']
    return json.dumps(dict(version=1, source_hash=data['source_hash'], mode='preserve',
        headline=None, lead=None, lead_additions=[],
        body_order=[p['id'] for p in data['body']], bold_subhead_ids=[], article=None))
with patch('texttools.ai_cli.run_ai_edit', side_effect=fake):
    main()
]=]
local command = { require('texttools_commands').bin('python'), '-c', stub }
vim.list_extend(command, vim.list_slice(requested.command, 2))
local result = original_system(command, { text = true, stdin = requested.stdin }):wait(5000)
assert(result.code == 0, result.stderr)
vim.api.nvim_buf_set_lines(buf, 1, 1, false, { 'rubriek: cultuur' })
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '---', '', '## Facebook', '', 'Handmatig bericht.' })
callback(result)
wait(function() return post ~= nil end)
assert(post.edit_mode == 'auto')
assert(text(buf):find('Foto: Anne Tester', 1, true) and text(buf):find('rubriek: cultuur', 1, true))
assert(text(buf):find('Handmatig bericht.', 1, true), 'staartsectie verdween')
assert(text(buf):find('Deze bronalinea blijft precies zo.\nDeze regel hoort bij dezelfde alinea.', 1, true))
assert(text(buf):find('**KAMPEN -', 1, true))
vim.api.nvim_buf_delete(buf, { force = true })

vim.system = original_system
dialog.select = original_select
ai._post_full_article_rewrite = original_post
print 'rewrite preservation: OK'
