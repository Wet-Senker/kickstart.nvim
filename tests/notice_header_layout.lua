dofile('tests/helpers/notice_clock.lua')
local activity = require 'article_activity'
local notices = require 'article_notices'
local revisions = require 'buffer_revision'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function wait(test) assert(vim.wait(1000, test, 5), 'kopindeling bleef hangen') end
local function lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function text(buf) return table.concat(lines(buf), '\n') end
local function row(buf, value)
  for index, line in ipairs(lines(buf)) do if line == value then return index end end
end
local yaml = { '---', 'media:', '  credit: Johan Schaart.', '  note: |',
  '    [12:34] Dit is YAML, geen editorstatus.', '', '    Tweede regel.', '---' }
local body = { '=== ARTIKEL ===', '', 'Kop', '', 'Artikeltekst.', '',
  '[12:34] Dit behoort tot de artikeltekst.', '', '## Kalender', '', 'Titel: Kerst' }
local buf = vim.api.nvim_create_buf(true, false)
local original = vim.list_extend(vim.deepcopy(yaml), { '', 'e: B',
  '[12:34] LET OP: Datum ontbreekt.', '', '[12:34] Herschreven met Persberichten bewerken.',
  'c: Johan Schaart.', '' })
vim.list_extend(original, body)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
local revision = revisions.capture(buf)
vim.api.nvim_set_current_buf(buf)
local expected = vim.list_extend(vim.deepcopy(yaml), { '', 'e: B', 'c: Johan Schaart.', '',
  '[12:34] LET OP: Datum ontbreekt.', '[12:34] Herschreven (<leader>ar).', '' })
vim.list_extend(expected, body)
wait(function() return vim.deep_equal(lines(buf), expected) end)
assert(not activity.snapshot(buf), 'heropenen verzon taak-/publicatiestatus')
assert(revisions.matches(buf, revision), 'alleen kopindeling maakte een bronrevisie ongeldig')
local normalized = notices.content_lines(lines(buf))
assert(vim.deep_equal(vim.list_slice(normalized, 1, #yaml), yaml), 'YAML-witruimte werd genegeerd')
assert(text(buf):find(table.concat(body, '\n'), 1, true), 'artikel/staartsectie gewijzigd')

-- Nieuwe metagegevens (zoals na een fotokeuze) gaan ook vóór bestaande
-- meldingen. De cursor blijft bij de instelling die de redacteur bewerkt.
local boundary = row(buf, '=== ARTIKEL ===')
vim.api.nvim_buf_set_lines(buf, boundary - 1, boundary - 1, false, { 'b: Nieuwe foto' })
vim.api.nvim_win_set_cursor(0, { boundary, 5 })
wait(function() return row(buf, 'b: Nieuwe foto') < row(buf, '[12:34] LET OP: Datum ontbreekt.') end)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { row(buf, 'b: Nieuwe foto'), 5 }), 'cursor verloor de bewerkte instelling')
assert(text(buf):find('e: B\nc: Johan Schaart.\nb: Nieuwe foto\n\n[12:34]', 1, true))

-- Beheerde meldingsankers overleven de verplaatsing; oplossen verwijdert
-- alleen die melding en dd blijft een bewuste afwijzing, ook na herschikken.
activity.record(buf, 'Vul een tijd in.', vim.log.levels.WARN, { action = 'Tijd' })
wait(function() return row(buf, '[12:34] LET OP: Vul een tijd in.') end)
boundary = row(buf, '=== ARTIKEL ===')
vim.api.nvim_buf_set_lines(buf, boundary - 1, boundary - 1, false, { 'agenda: ja' })
wait(function() return row(buf, 'agenda: ja') < row(buf, '[12:34] LET OP: Vul een tijd in.') end)
activity.record(buf, 'Tijd ingevuld.', nil, { action = 'Tijd', kind = 'success' })
wait(function() return not row(buf, '[12:34] LET OP: Vul een tijd in.') end)
assert(row(buf, '[12:34] LET OP: Datum ontbreekt.'))
activity.record(buf, 'Controleer de credit.', vim.log.levels.WARN, { action = 'Credit' })
wait(function() return row(buf, '[12:34] LET OP: Controleer de credit.') end)
vim.api.nvim_win_set_cursor(0, { row(buf, '[12:34] LET OP: Controleer de credit.'), 0 })
vim.cmd 'normal! dd'
local tick = vim.api.nvim_buf_get_changedtick(buf)
activity.record(buf, 'Technische notitie.', nil, { detail = true })
vim.wait(30, function() return false end)
assert(not row(buf, '[12:34] LET OP: Controleer de credit.') and activity.snapshot(buf).issues.Credit)
assert(vim.api.nvim_buf_get_changedtick(buf) == tick, 'ongewijzigde indeling bleef herschrijven')

-- Geen herindeling tijdens werk dat een bronrevisie gebruikt.
activity.start(buf, 'busy', 'Controleren')
boundary = row(buf, '=== ARTIKEL ===')
vim.api.nvim_buf_set_lines(buf, boundary - 1, boundary - 1, false, { 'prio: 2' })
tick = vim.api.nvim_buf_get_changedtick(buf)
vim.wait(30, function() return false end)
assert(vim.api.nvim_buf_get_changedtick(buf) == tick)
activity.finish(buf, 'busy')
wait(function() return row(buf, 'prio: 2') < row(buf, '[12:34] LET OP: Datum ontbreekt.') end)
assert(text(buf):find(table.concat(body, '\n'), 1, true))
print('notice header layout: OK')
