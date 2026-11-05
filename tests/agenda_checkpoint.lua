local ai = require 'ai_text'
local transport = require 'agenda_checkpoint'
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', 'Concert', '', 'KAMPEN - Muziek.' })
  return buf
end
local state = { version = 1, source = 'opaque-core-signature', scope = { 'B' },
  checked_at = 1234, result = { performed = true, candidates = {}, errors = {}, checked_events = {} } }
local payload = { combined = true, candidates = {}, checks = {
  web = { requested = true, complete = true, performed = true },
  agenda = { requested = true, complete = true, performed = true, bron = 'kalenderblok', checkpoint = state } } }
local function saved(buf)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match('^agenda_duplicate_check:') then
      return vim.json.decode(line:match('^agenda_duplicate_check: (.*)$'))
    end
  end
end
local buf = source()
ai._duplicate_stage_runner = function(_, done) done(true, vim.deepcopy(payload)) end
local completed
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) completed = ok end)
assert(completed and vim.deep_equal(saved(buf), state), 'complete controle niet opgeslagen')
local original = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
transport.remember(buf, { checkpoint = state })
assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'gelijke checkpoint veroorzaakte een nieuwe edit')
local before_body = table.concat(original, '\n')
assert(before_body:find('=== ARTIKEL ===\n\nConcert\n\nKAMPEN - Muziek.', 1, true))
-- Na herschrijven gaat het documentcheckpoint mee naar de gezamenlijke kernactie.
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwe formulering.' })
ai._duplicate_stage_runner = function(command, done)
  assert(table.concat(vim.fn.readfile(command[2]), '\n'):find('agenda_duplicate_check:', 1, true))
  done(true, vim.deepcopy(payload))
end
ai._check_duplicate_stage(buf, { 'B' }, 'herschrijven', function(ok) assert(ok) end)
-- Een oude callback mag geen complete controle voor nieuwere tekst vastleggen.
local stale = source()
local reply
ai._duplicate_stage_runner = function(_, done) reply = done end
ai._check_duplicate_stage(stale, { 'B' }, 'importeren', function() end)
vim.api.nvim_buf_set_lines(stale, -1, -1, false, { 'Nieuwere evenementgegevens.' })
reply(true, vim.deepcopy(payload))
assert(not saved(stale), 'oude controle werd voor nieuwere bron bewaard')
-- Een onvolledige controle is geen checkpoint.
local failed = source()
ai._duplicate_stage_runner = function(_, done)
  local data = vim.deepcopy(payload); data.checks.agenda.complete = false
  done(true, data)
end
ai._check_duplicate_stage(failed, { 'B' }, 'importeren', function() end)
assert(not saved(failed), 'onvolledige controle is als geldig bewaard')
print('agenda checkpoint: OK')

-- Het opslaan van expliciete keuzes verandert frontmatter, niet de controlebron.
local selected = source()
local selected_reply
ai._duplicate_stage_runner = function(_, done) selected_reply = done end
ai._check_duplicate_stage(selected, { 'B' }, 'importeren', function() end)
vim.api.nvim_buf_set_lines(selected, 0, 0, false, { '---', 'duplicate_selection: {version: 1, entries: []}', '---' })
local selected_data = vim.deepcopy(payload); selected_data.selection_applied = true
selected_reply(true, selected_data)
assert(vim.deep_equal(saved(selected), state), 'eigen reviewmetadata liet de controle vervallen')
-- Een oudere callback overschrijft geen nieuwer resultaat.
local fresh = vim.deepcopy(state); fresh.checked_at = 2345
transport.remember(selected, { checkpoint = fresh })
transport.remember(selected, { checkpoint = state })
assert(saved(selected).checked_at == 2345)

-- Python-reviewacties mogen dezelfde checkpoint ook als meerregelige YAML opslaan.
local multiline = source()
vim.api.nvim_buf_set_lines(multiline, 0, 0, false, {
  '---', 'agenda_duplicate_check:', '  version: 1', '  checked_at: 3456',
  '  source: vorige-controle', '  result:', '    performed: true',
  'other_metadata: behouden', '---', '' })
local multiline_before = vim.api.nvim_buf_get_lines(multiline, 0, -1, false)
transport.remember(multiline, { checkpoint = fresh })
assert(vim.deep_equal(multiline_before, vim.api.nvim_buf_get_lines(multiline, 0, -1, false)),
  'nieuwere YAML-checkpoint overschreven')
local latest = vim.deepcopy(fresh); latest.checked_at = 4567
transport.remember(multiline, { checkpoint = latest })
local markdown = table.concat(vim.api.nvim_buf_get_lines(multiline, 0, -1, false), '\n')
local parsed = vim.system({ require('texttools_commands').bin('python'), '-c', [[
import json,sys
from texttools.article_document import split_existing_frontmatter,parse_existing_frontmatter
fm,body=split_existing_frontmatter(sys.stdin.read())
print(json.dumps({'metadata':parse_existing_frontmatter(fm),'body':body}))
]] }, { text = true, stdin = markdown }):wait()
assert(parsed.code == 0, parsed.stderr)
local decoded = vim.json.decode(parsed.stdout)
assert(decoded.metadata.agenda_duplicate_check.checked_at == 4567)
assert(decoded.metadata.other_metadata == 'behouden')
assert(decoded.body:find('KAMPEN - Muziek.', 1, true))
