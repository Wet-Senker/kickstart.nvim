-- The real aw/review/apply boundary, with only CMS/publication calls replaced.
local ai = require 'ai_text'
local commands = require 'texttools_commands'
local native_system = vim.system
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = directory
local recognition = require 'article_recognition'
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end
require('publication_dates').review = function(_, _, _, _, done) done('ready') end
ai._calendar_edition_resolver = function(_, _, done) done { editions = { 'B', 'SW' } } end
local scans, sends = 0, 0
local source, current_report
local function wait(test) assert(vim.wait(4000, test, 5), 'send/review did not finish') end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function key(buf, name)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs == name then mapping.callback(); return end
  end
  error('missing key ' .. name)
end
local function row(headline)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(headline, 1, true) then vim.api.nvim_win_set_cursor(0, { index, 0 }); return end
  end
  error('missing headline ' .. headline)
end
local empty = vim.api.nvim_create_buf(false, true)
local original_resolver = ai._calendar_edition_resolver
ai._calendar_edition_resolver = function() error('empty buffer triggered a resolver') end
ai.pubble_send(empty)
ai._calendar_edition_resolver = original_resolver
ai._duplicate_stage_runner = function(_, done, options)
  scans = scans + 1
  local result = native_system({ commands.bin('python'), '-c', [[
import json,sys
from texttools.duplicate_selection import annotate_report
print(json.dumps(annotate_report(sys.stdin.read(), ['B','SW'], {
 'version':1, 'combined':True, 'performed':True, 'history_complete':True, 'errors':[],
 'checks':{'web':{'requested':True,'complete':True,'performed':True},
           'agenda':{'requested':False,'complete':True,'performed':False}},
 'candidates':[{'key':'join:123','kind':'web','variants':[
  {'edition':'B','article_id':123,'headline':'Treffer Brug'},
  {'edition':'SW','article_id':124,'headline':'Treffer Zwolle'}]},
  {'key':'join:125','kind':'web','variants':[
   {'edition':'B','article_id':125,'headline':'Tweede treffer Brug'}]}]
})))
]] }, { text = true, stdin = text(source) }):wait()
  assert(result.code == 0, result.stderr)
  current_report = vim.json.decode(result.stdout)
  require('pubble_duplicates').show(current_report, function(ok) done(ok, current_report) end, options)
end
vim.system = function(command, options, done)
  if not command[1]:match('pubble%-send$') then return native_system(command, options, done) end
  assert(vim.tbl_contains(command, '--create'), 'unexpected second resolver/planning call')
  sends = sends + 1
  local staged = table.concat(vim.fn.readfile(command[2]), '\n')
  assert(staged:find('duplicate_selection:', 1, true), 'saved choices missing from actual send')
  assert(staged:find('e: B, SW', 1, true), 'q/n changed the selected editions')
  vim.schedule(function() done { code = 1, stdout = '', stderr = 'Offline publication stub.' } end)
  return { kill = function() end }
end

for index, mode in ipairs { 'all-different', 'duplicate', 'edited', 'cancel' } do
  source = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_set_name(source, directory .. '/werk/article-' .. index .. '.md')
  vim.api.nvim_buf_set_lines(source, 0, -1, false, {
    'e: B, SW', 'agenda: nee', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Bericht.' })
  vim.b[source].publication_review_state = { editions = { 'B', 'SW' }, display_dates = {},
    skip_newspaper_editions = { 'B', 'SW' } }
  local before_scans, before_sends = scans, sends
  ai.pubble_send(source)
  wait(function() return vim.api.nvim_buf_get_name(0):find('Pubble doublurecontrole', 1, true) ~= nil end)
  local dialog = vim.api.nvim_get_current_buf()
  assert(text(dialog):find('[Geen doublure · verzenden]', 1, true))
  assert(not text(dialog):find('Onbeoordeeld', 1, true) and not text(dialog):find('Webdoublure:', 1, true))
  if mode == 'edited' then
    vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere eigen artikeltekst.' })
  end
  key(dialog, mode == 'duplicate' and 'm' or mode == 'cancel' and 'q' or 'n')
  wait(function() return not vim.api.nvim_buf_is_valid(dialog) and
    (vim.b[source].pending_jobs or 0) == 0 and not vim.b[source].calendar_send_review_pending end)
  if mode == 'edited' then
    assert(sends == before_sends and text(source):find('Nieuwere eigen artikeltekst.', 1, true), 'newer text was published/lost')
    assert(not ai._duplicate_check_is_current(source))
  elseif mode == 'duplicate' or mode == 'cancel' then
    assert(sends == before_sends, 'afwijzen of uitstellen verzond het artikel')
    assert(not text(source):find('duplicate_selection:', 1, true), 'stoppen verzon een specifieke doublurereferentie')
  else
    wait(function() return sends == before_sends + 1 and vim.b[source].publication_in_progress == false end)
    assert(ai._duplicate_check_is_current(source), 'metadata-only apply lost the completed review')
    local approved
    ai._check_duplicate_stage(source, { 'B', 'SW' }, 'verzenden', function(ok) approved = ok end)
    assert(approved and scans == before_scans + 1, 'same review was requested twice')
    if mode == 'q' then assert(not text(source):find('decision: different', 1, true), 'q invented a no-duplicate decision') end
  end
  assert(scans == before_scans + 1, 'one send performed multiple scans')
end
vim.system = native_system
vim.fn.delete(directory, 'rf')
print('duplicate send continuation: OK')
