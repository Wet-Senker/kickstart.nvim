-- Echt Pythonrapport en lokale validatie; geen AI of CMS.
vim.notify = function() end
local client = require('quote_review')
local editor = require('editorial_review')
local python = require('texttools_commands').bin('python')
local source = 'Bronkop\n\nZWOLLE - Ard doet mee.\n\nArd: "Ik wil graag bruggen slaan naar werelden die verder van groen staan."'
local proposal = source:gsub('bruggen slaan', 'mensen verbinden')
local generated = vim.system({ python, '-c', [[
import json, sys
from texttools.quote_review import prepare_quote_review
p=json.load(sys.stdin)
print(json.dumps(prepare_quote_review(p['source'], p['article']).to_dict()))
]] }, { text = true, stdin = vim.json.encode({ source = source, article = proposal }) }):wait()
assert(generated.code == 0, generated.stderr)
local report = vim.json.decode(generated.stdout)
assert(editor.valid_report(report, source) and client.valid_report(report, source))
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(source, '\n', { plain = true }))
local accepted, kept = 0, 0
local generation = 1
local function open()
  local current_generation = generation
  assert(client.handle({ code = 3, stdout = generated.stdout }, {
    buf = buf, source = source,
    is_current = function() return vim.api.nvim_buf_is_valid(buf) and generation == current_generation
      and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') == source end,
    ready = function(text) accepted = accepted + 1; assert(text == source) end,
    fail = function() kept = kept + 1 end,
  }))
  return assert(client.active(buf))
end
local session = open()
assert(#session.windows == 2 and #session.buffers == 2, 'geen compacte vergelijking')
assert(not vim.bo[session.original].modifiable and vim.bo[session.proposal].modifiable)
assert(#vim.api.nvim_buf_get_extmarks(session.original, client.namespace, 0, -1, {}) == 1)
assert(#vim.api.nvim_buf_get_extmarks(session.proposal, client.namespace, 0, -1, {}) == 1)
assert(vim.b[buf].texttools_pending_quote_review)
session.accept()
assert(vim.wait(2000, function() return not session.validating end))
assert(accepted == 0 and not session.closed, 'afwijkend citaat onterecht overgenomen')
vim.api.nvim_buf_set_lines(session.proposal, 0, -1, false, vim.split(source, '\n', { plain = true }))
session.accept()
assert(vim.wait(2000, function() return session.closed end))
assert(accepted == 1 and not vim.b[buf].texttools_pending_quote_review)
vim.wait(20, function() return false end)
session = open()
session.keep()
assert(kept == 1 and accepted == 1)
vim.wait(20, function() return false end)
session = open()
generation = generation + 1
session.accept()
assert(not session.closed and accepted == 1, 'nieuwere opdracht overschreven')
session.keep()
vim.wait(20, function() return false end)
-- Een edit in het voorstel tijdens de lokale hercontrole kan niet worden gewist.
session = open()
vim.api.nvim_buf_set_lines(session.proposal, 0, -1, false, vim.split(source, '\n', { plain = true }))
local native_system, answer = vim.system, nil
vim.system = function(_, _, done) answer = done; return {} end
local accepted_before = accepted
session.accept()
assert(session.validating and answer)
vim.api.nvim_buf_set_lines(session.proposal, 0, 1, false, { 'Nieuwere eigen kop' })
answer({ code = 0, stdout = vim.json.encode({ version = 1, kind = 'quote_review', status = 'ready',
  source_sha256 = vim.fn.sha256(source), article = source, issues = {}, quote_differences = {} }) })
assert(vim.wait(1000, function() return not session.validating end))
assert(not session.closed and accepted == accepted_before, 'late hercontrole overschreef voorstel-edit')
assert(vim.api.nvim_buf_get_lines(session.proposal, 0, 1, false)[1] == 'Nieuwere eigen kop')
vim.system = native_system
session.keep()
vim.wait(20, function() return false end)
-- Een ontbrekend lokaal proces houdt aY niet voor altijd vast.
session = open()
local previous_system = vim.system
vim.system = function() error('bewuste lokale startfout') end
session.accept()
assert(not session.validating and not session.closed, 'lokale startfout zette review vast')
vim.system = previous_system
session.keep()
vim.wait(20, function() return false end)
-- Handmatig sluiten maakt de oorspronkelijke tekst weer bewerkbaar/verzendbaar.
session = open()
vim.cmd('tabclose')
assert(vim.wait(1000, function() return session.closed end))
assert(not vim.b[buf].texttools_pending_quote_review)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') == source)
-- Onbekende foutcodes openen geen vergelijking; corrupte JSON kan geen body zijn.
assert(not client.handle({ code = 1, stderr = 'Netwerkfout' }, {}))
local failed = false
assert(client.handle({ code = 3, stdout = '{}' }, { source = source, fail = function() failed = true end }))
assert(failed)
print('quote review: OK')
