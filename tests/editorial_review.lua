vim.notify = function() end
local review = require('editorial_review')
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'Bronkop', '', '18 woningen op 22 oktober.' })
local original = vim.api.nvim_buf_get_lines(source, 0, -1, false)
local body = table.concat(original, '\n')
local report = { version = 1, source_sha256 = vim.fn.sha256(body), status = 'needs_review',
  article = 'Nieuwe kop\n\n18 woningen op 22 november.',
  issues = { { code = 'dates', message = 'Datums: verdwenen: 22-10; toegevoegd: 22-11.' } } }
assert(review.valid_report(report, body))
-- Echt Python->JSON->Lua-contract, met uitsluitend de AI-adapter gemockt.
local python = vim.env.TEXTTOOLS_ROOT .. '/.venv/bin/python'
local prepared = vim.system({ python, '-c', [=[
import json, sys
from texttools.journalistic_neutrality import prepare_journalistic_neutrality
data = json.loads(sys.stdin.read())
outputs = iter(['{"remove_line_numbers": []}', data['article']])
print(json.dumps(prepare_journalistic_neutrality(data['source'], runner=lambda **_: next(outputs)).to_dict()))
]=] }, { text = true, stdin = vim.json.encode({ source = body, article = report.article }) }):wait()
assert(prepared.code == 0, prepared.stderr)
local actual = vim.json.decode(prepared.stdout)
assert(review.valid_report(actual, body) and actual.status == 'needs_review')
assert(actual.issues[1].code == 'dates', 'kern en client verschillen over de datumcontrole')
assert(not review.valid_report(report, 'andere bron'))
local malformed = vim.deepcopy(report)
malformed.status = 'ready'
assert(not review.valid_report(malformed, body))
malformed = vim.deepcopy(report); malformed.article = '  '
assert(not review.valid_report(malformed, body))

local accepted = 0
local function open()
  local tick = vim.api.nvim_buf_get_changedtick(source)
  return review.open({ source_buf = source, original = original, report = report,
    is_current = function() return vim.api.nvim_buf_is_valid(source)
      and vim.api.nvim_buf_get_changedtick(source) == tick end,
    on_accept = function(lines)
      accepted = accepted + 1
      vim.api.nvim_buf_set_lines(source, 0, -1, false, lines)
    end })
end
local session = open()
assert(#session.windows == 3, 'controlepunten en twee artikelen ontbreken')
assert(vim.wo[session.windows[2]].diff and vim.wo[session.windows[3]].diff, 'geen gemarkeerde vergelijking')
assert(vim.wo[session.windows[2]].winbar:find('Onbewerkt', 1, true))
assert(vim.wo[session.windows[3]].winbar:find('Bewerkt', 1, true))
assert(not vim.bo[session.buffers[2]].modifiable, 'origineel is niet beschermd')
assert(vim.bo[session.proposal].modifiable, 'voorstel kan niet worden aangepast')
for _, key in ipairs(vim.api.nvim_buf_get_keymap(session.proposal, 'n')) do
  assert(key.lhs ~= '<Esc>', 'Escape heeft onterecht een reviewactie')
end
local ai = require('ai_text')
local original_system, requests = vim.system, 0
vim.system = function() requests = requests + 1; error('voorstel mag niet publiceren') end
for _, buf in ipairs(session.buffers) do ai.pubble_send(buf) end
vim.system = original_system
assert(requests == 0, 'verzendguard raakte een extern proces')
vim.api.nvim_buf_set_lines(session.proposal, 0, 1, false, { 'Mijn gecontroleerde kop' })
vim.api.nvim_buf_call(session.proposal, function() vim.cmd('ArtikelBewerkingOvernemen') end)
assert(accepted == 1 and vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == 'Mijn gecontroleerde kop')
assert(session.closed and not vim.api.nvim_tabpage_is_valid(session.tab), 'reviewweergave bleef achter')
assert(vim.api.nvim_get_current_buf() == source)

local saved = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n')
session = open()
vim.api.nvim_buf_call(session.proposal, function() vim.cmd('ArtikelBewerkingBehouden') end)
assert(accepted == 1 and table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n') == saved)

session = open()
vim.api.nvim_buf_set_lines(source, 0, 1, false, { 'Nieuwere eigen kop' })
session.accept()
assert(not session.closed and accepted == 1, 'laat voorstel overschreef nieuwere bron')
assert(vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == 'Nieuwere eigen kop')
session.keep()

session = open()
vim.api.nvim_buf_set_lines(session.proposal, 0, -1, false, { '' })
session.accept()
assert(not session.closed and accepted == 1, 'leeg voorstel werd overgenomen')
session.keep()

session = open()
vim.api.nvim_buf_delete(source, { force = true })
session.accept()
assert(not session.closed and accepted == 1, 'voorstel ging naar een verdwenen bron')
session.keep()
print('editorial review: OK')
