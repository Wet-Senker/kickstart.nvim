local ai = require 'ai_text'
local ui = require 'pubble_duplicates'
local commands = require 'texttools_commands'
local native_system = vim.system
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function wait(test) assert(vim.wait(4000, test, 5), 'doublurekeuze bleef wachten') end
local function key(buf, name)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs:lower() == name:lower() then mapping.callback(); return end
  end
  error('toets ontbreekt: ' .. name)
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function row_contains(word)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(word, 1, true) then vim.api.nvim_win_set_cursor(0, { row, 0 }); return line end
  end
  error('regel ontbreekt: ' .. word)
end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B, SW', '', '=== ARTIKEL ===', '', 'Concert', '',
    'KAMPEN - Een concert op 18 november 2099.' })
  return buf
end
local function report(buf)
  local script = [[
import json,sys
from texttools.duplicate_selection import annotate_report
source=sys.stdin.read()
print(json.dumps(annotate_report(source,['B','SW'],{
 'version':1,'combined':True,'performed':True,'history_complete':True,'errors':[],
 'checks':{'web':{'performed':True,'requested':True,'complete':True},
           'agenda':{'performed':True,'requested':True,'complete':True}},
 'candidates':[{'key':'join:123','kind':'web',
   'comparison':{'date':'2099-11-18','headline':'Concert'},'variants':[
   {'edition':'B','publication':'De Brug','article_id':123,'headline':'Concert Brug','text':'Een concert.'},
   {'edition':'SW','publication':'De Swollenaer','article_id':124,'headline':'Concert Zwolle','text':'Een concert.'}]}]
})))
]]
  local result = native_system({ commands.bin('python'), '-c', script }, { text = true, stdin = text(buf) }):wait()
  assert(result.code == 0, result.stderr)
  return vim.json.decode(result.stdout)
end

-- Production report and production Python apply; only the CMS reader is replaced.
ai._duplicate_stage_runner = function(_, callback, options)
  local data = report(options.buf)
  ui.show(data, function(ok) callback(ok, data) end, options)
end
local buf, result = source(), nil
ai._check_duplicate_stage(buf, { 'B', 'SW' }, 'verzenden', function(ok) result = ok end)
local dialog = vim.api.nvim_get_current_buf()
assert(text(dialog):find('Bestaand webartikel:', 1, true), 'bestaande webtekst niet herkenbaar gelabeld')
assert(text(dialog):find('Jouw huidige bericht: 18-11-2099', 1, true)
  and text(dialog):find(')  Concert', 1, true),
  'huidig bericht mist een duidelijk vergelijkingslabel of dezelfde datumweergave')
assert(not text(dialog):find('dezelfde toets nogmaals', 1, true), 'overbodige toetsuitleg bleef in overzicht')
row_contains('Concert Brug'); key(dialog, 'm')
assert(row_contains('Concert Brug'):find('[=]', 1, true))
assert(result == nil, 'markering sloot de review of startte publicatie')
key(dialog, 'm'); assert(row_contains('Concert Brug'):find('[ ]', 1, true))
key(dialog, 'n'); assert(row_contains('Concert Brug'):find('[≠]', 1, true))
key(dialog, 'n'); key(dialog, 'm')
-- Enter/q inspect, without applying or changing the mark.
key(dialog, '<CR>'); assert(text(dialog):find('Een concert.', 1, true))
key(dialog, 'q'); assert(result == nil)
key(dialog, 'q')
wait(function() return result ~= nil end)
assert(result == false, 'q vanuit aw publiceerde impliciet')
assert(text(buf):find('duplicate_selection:', 1, true) and text(buf):find('decision: duplicate', 1, true))
assert(not vim.b[buf].send_requested)
local stored = report(buf)
assert(#stored.saved_selections == 1 and stored.saved_selections[1].edition == 'B')
assert(#stored.candidates[1].variants == 1 and stored.candidates[1].variants[1].edition == 'SW')

-- Closing without marks is an editing decision, not a confirmed duplicate.
buf, result = source(), nil
ai._check_duplicate_stage(buf, { 'B', 'SW' }, 'importeren', function(ok) result = ok end)
key(vim.api.nvim_get_current_buf(), 'q')
wait(function() return result ~= nil end)
assert(result and #report(buf).saved_selections == 0)

-- A late apply cannot overwrite newer text (real asynchronous Python process).
buf = source()
local view, applied = report(buf), nil
require('duplicate_review').apply(buf, view, {}, function(ok) applied = ok end)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwste eigen tekst.' })
wait(function() return applied ~= nil end)
assert(not applied and text(buf):find('Nieuwste eigen tekst.', 1, true))
assert(not text(buf):find('duplicate_selection:', 1, true))

-- Explicit pause cancels automatic agenda continuation and stores no choices.
buf, result = source(), nil
ai._check_duplicate_stage(buf, { 'B', 'SW' }, 'importeren', function(ok) result = ok end)
dialog = vim.api.nvim_get_current_buf()
row_contains('Concert Brug'); key(dialog, 'm'); key(dialog, '<C-c>')
wait(function() return result ~= nil end)
assert(not text(buf):find('duplicate_selection:', 1, true))
assert(vim.b[buf].calendar_autodetect_suppressed)

-- An agenda proposal is reviewed before insertion. Persist only the decisions,
-- never overwrite the source body or silently insert the proposal during q.
buf = source()
local proposal = source()
vim.api.nvim_buf_set_lines(proposal, -1, -1, false, { '', '---', '', '## Kalender', '', 'Titel: Concert', 'Datum: 2099-11-18' })
local proposed_text = text(proposal)
local view = report(proposal)
vim.api.nvim_set_current_buf(buf)
result = nil
ai._agenda_duplicate_confirm(buf, { selection_report = view, reviewed_markdown = proposed_text }, function(ok) result = ok end)
dialog = vim.api.nvim_get_current_buf()
row_contains('Concert Brug'); key(dialog, 'm'); key(dialog, 'q')
wait(function() return result ~= nil end)
assert(result and text(buf):find('duplicate_selection:', 1, true))
assert(not text(buf):find('## Kalender', 1, true))

-- Het agenda-item en de huidige bron vormen één vergelijking, geen twee
-- categorieën. Beide regels blijven hetzelfde selecteerbare paar aanwijzen.
local agenda_report = { candidates = { { kind = 'agenda',
  comparison = { date = '2026-11-05', headline = 'Mijn huidige concertbericht' },
  variants = { { publication = 'De Swollenaer', kind = 'agenda',
    display_date_short = '05-11-2026', headline = 'Bestaand concert',
    review_selectable = true, review_target = { id = 'agenda-pair' } } },
} } }
local selected_choices
require('duplicate_selection_ui').show(agenda_report, function() end, {
  on_apply = function(_, choices, done)
    selected_choices = choices
    done(true)
  end,
})
dialog = vim.api.nvim_get_current_buf()
assert(row_contains('Bestaand agenda-item:'):find('05-11-2026', 1, true))
assert(row_contains('Jouw huidige bericht:'):find('05-11-2026', 1, true))
key(dialog, 'n')
assert(row_contains('Bestaand agenda-item:'):find('[≠]', 1, true), 'vergelijkingsregel verloor koppeling met bestaand item')
key(dialog, 'q')
assert(selected_choices['agenda-pair'] == 'different', 'labels veranderden de opgeslagen keuze')

print('duplicate_selection: ok')
