dofile('tests/helpers/notice_clock.lua')
local activity = require 'article_activity'
assert(require('article_notices').summary('Herschrijven niet toegepast. Citaatcontrole geweigerd: de herschrijving maakte een nieuw citaat.', true)
  == 'Herschrijven niet toegepast: citaat wijkt af. Bekijk <leader>kl en controleer de genoemde bronpassage.')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function article()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'Mijn tekst.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function count(buf)
  local n = 0
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do if line:match('^%[12:34%]') then n = n + 1 end end
  return n
end
local function row(buf, needle)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find(needle, 1, true) then return index end
  end
end
local function wait(test) assert(vim.wait(1000, test, 5), 'meldingsregels bleven hangen') end
local a = article()
local ai = require 'ai_text'
local body = ai._editorial_body_text(vim.api.nvim_buf_get_lines(a, 0, -1, false))
activity.record(a, 'Kalendergegevens toegevoegd.', nil, { inline = true, notice_key = 'calendar', kind = 'success' })
wait(function() return count(a) == 1 end)
assert(text(a):find('e: B\n\n=== LOG ===\n[12:34] Kalendergegevens toegevoegd.\n\n=== ARTIKEL ===', 1, true))
assert(not text(a):find('LET OP', 1, true), 'succes kreeg een waarschuwing')
assert(not activity.panel_visible(a))
assert(#vim.api.nvim_buf_get_extmarks(a, require('article_notices').namespace, 0, -1, {}) == 0, 'virtuele dubbeling')
-- Normale yy/dd-bediening, geen nieuwe mappings of popup nodig.
vim.api.nvim_win_set_cursor(0, { row(a, '[12:34]'), 0 })
vim.cmd('normal! yy')
assert(vim.fn.getreg('"'):find('Kalendergegevens toegevoegd.', 1, true))
vim.cmd('normal! dd')
wait(function() return count(a) == 0 end)
activity.record(a, 'Technisch detail', nil, { detail = true })
vim.wait(20, function() return false end)
assert(count(a) == 0, 'verwijderde melding kwam vanzelf terug')
assert(activity.snapshot(a).entries[1].message == 'Kalendergegevens toegevoegd.', 'dd wiste historie')
-- Nieuwe uitkomst vervangt de vorige en heeft alleen bij ontbreken LET OP.
activity.record(a, 'Kalendergegevens toegevoegd. LET OP: Datum ontbreekt. Vul aan bij ## Kalender.', vim.log.levels.WARN,
  { inline = true, notice_key = 'calendar', resolved = true })
wait(function() return count(a) == 1 end)
assert(not text(a):find('LET OP: Kalendergegevens', 1, true))
activity.record(a, 'Kalendergegevens toegevoegd.', nil,
  { inline = true, notice_key = 'calendar', resolved = true, kind = 'success' })
wait(function() return count(a) == 1 and not text(a):find('Datum ontbreekt', 1, true) end)
assert(not activity.snapshot(a).issues.calendar)
assert(ai._editorial_body_text(vim.api.nvim_buf_get_lines(a, 0, -1, false)) == body)
local normalized = require('article_notices').content_lines(vim.api.nvim_buf_get_lines(a, 0, -1, false))
assert(not table.concat(normalized, '\n'):find('[12:34]', 1, true), 'statusregel vervuilt vergelijkingssnapshot')
assert(require('article_notices').content_lines({ '[12:34] gewone bron' })[1] == '[12:34] gewone bron')
local path = vim.fn.tempname() .. '.md'
vim.api.nvim_buf_set_name(a, path)
vim.cmd('silent write')
assert(table.concat(vim.fn.readfile(path), '\n'):find('[12:34]', 1, true))
-- Automatische statusregels maken lopend werk niet verouderd.
activity.start(a, 'running', 'Controleren')
local tick = vim.api.nvim_buf_get_changedtick(a)
activity.record(a, 'Facebook-tekst toegevoegd.', nil, { inline = true, notice_key = 'facebook', kind = 'success' })
vim.wait(20, function() return false end)
assert(vim.api.nvim_buf_get_changedtick(a) == tick)
activity.finish(a, 'running')
wait(function() return text(a):find('[12:34] Facebook-tekst toegevoegd.', 1, true) end)
-- Weggehaalde waarschuwing verandert geen onderliggende controle.
activity.record(a, 'Fotocredit ontbreekt. Vul c: in.', vim.log.levels.WARN, { action = 'Fotocredit' })
wait(function() return text(a):find('[12:34] LET OP: Fotocredit', 1, true) end)
vim.api.nvim_win_set_cursor(0, { row(a, '[12:34] LET OP: Fotocredit'), 0 })
vim.cmd('normal! dd')
wait(function() return not text(a):find('[12:34] LET OP: Fotocredit', 1, true) end)
assert(activity.snapshot(a).issues.Fotocredit)
activity.record(a, 'Foto gecontroleerd.', nil, { kind = 'success', action = 'Fotocredit' })
wait(function() return not activity.snapshot(a).issues.Fotocredit end)
-- Bronbinding en vervangen document: niet oude regels terugzetten.
local b = article()
activity.record(b, 'Andere bron.', nil, { inline = true, notice_key = 'other' })
wait(function() return count(b) == 1 end)
assert(not text(a):find('Andere bron.', 1, true))
vim.api.nvim_buf_set_lines(b, 0, 0, false, { 'Een kopregel' })
vim.wait(20, function() return false end)
assert(count(b) == 1 and row(b, '[12:34]') < row(b, '=== ARTIKEL ==='))
vim.api.nvim_buf_set_lines(b, 0, -1, false, { 'e: B', '=== ARTIKEL ===', 'Nieuwe body' })
vim.wait(20, function() return false end)
assert(count(b) == 0)
vim.fn.delete(path)
print('article notices: OK')
