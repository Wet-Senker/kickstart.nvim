-- Tijd hoort bij het resultaat, ook na uitgestelde weergave of heropenen.
local real_date, clock = os.date, '23:58'
os.date = function(format, ...)
  if format == '%H:%M' then return clock end
  return real_date(format, ...)
end
local activity, notices = require('article_activity'), require('article_notices')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function flush() vim.wait(40, function() return false end) end
local function wait(test) assert(vim.wait(2000, test, 5), 'tijd/volgorde bleef hangen') end
local function rows(buf)
  local result, above = {}, true
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line == '=== ARTIKEL ===' then above = false end
    if above and notices.is_line(line) then result[#result + 1] = line end
  end
  return result
end
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: SW', 'Melding: Import opgeschoond (zonder AI).', '', '=== ARTIKEL ===', '',
  'Kop', '', '[12:34] Dit is artikeltekst.', 'Melding: Dit is ook artikeltekst.',
})
wait(function() return rows(buf)[1] == '[--:--] Import opgeschoond (zonder AI).' end)
local revision = require('buffer_revision').capture(buf)
activity.record(buf, 'Eerste handeling.', nil, { inline = true, notice_key = 'first' })
wait(function() return #rows(buf) == 2 end)
assert(rows(buf)[2] == '[23:58] Eerste handeling.')
activity.start(buf, 'busy', 'Controleren')
clock = '23:59'
activity.record(buf, 'Tweede handeling.', vim.log.levels.WARN, { action = 'second' })
clock = '00:00'
activity.record(buf, 'Derde handeling.', vim.log.levels.ERROR, { action = 'third' })
clock = '00:01'
activity.finish(buf, 'busy')
wait(function() return #rows(buf) == 4 end)
assert(vim.deep_equal(rows(buf), {
  '[--:--] Import opgeschoond (zonder AI).', '[23:58] Eerste handeling.',
  '[23:59] LET OP: Tweede handeling.', '[00:00] FOUT: Derde handeling.',
}), 'ernst, late weergave of middernacht veranderde gebeurtenisvolgorde')
assert(require('buffer_revision').matches(buf, revision), 'tijdregels wijzigden de inhoudsrevisie')
-- Nieuwe uitkomst voor dezelfde groep komt onderaan, niet op de oude plek.
activity.record(buf, 'Eerste handeling opnieuw.', nil, { inline = true, notice_key = 'first' })
wait(function() return rows(buf)[4] == '[00:01] Eerste handeling opnieuw.' end)
assert(rows(buf)[2] == '[23:59] LET OP: Tweede handeling.')
-- Herhaling van dezelfde laatste boodschap hergebruikt de historie-ID, maar
-- krijgt de tijd van de nieuwe handeling. Refresh zelf verandert geen tijd.
clock = '00:02'
activity.record(buf, 'Eerste handeling opnieuw.', nil, { inline = true, notice_key = 'first' })
wait(function() return rows(buf)[4] == '[00:02] Eerste handeling opnieuw.' end)
local stable = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
clock = '10:00'
vim.api.nvim_exec_autocmds('BufEnter', { buffer = buf })
vim.api.nvim_exec_autocmds('VimResized', {})
flush()
assert(vim.deep_equal(stable, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
-- Bewaren/heropenen behoudt tijden én volgorde, zonder sessiestate te verzinnen.
local reopened = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(reopened, 0, -1, false, stable)
vim.api.nvim_set_current_buf(reopened)
flush()
assert(vim.deep_equal(rows(buf), rows(reopened)))
assert(not activity.snapshot(reopened))
local content = table.concat(notices.content_lines(stable), '\n')
assert(content:find('[12:34] Dit is artikeltekst.', 1, true))
assert(content:find('Melding: Dit is ook artikeltekst.', 1, true))
for _, invalid in ipairs { '[24:00] Fout', '[12:60] Fout', '[9:30] Geen contract', '[12:34]geen spatie' } do
  assert(not notices.is_line(invalid))
end
-- Virtuele fallback volgt dezelfde gebeurtenisvolgorde, niet ernstvolgorde.
local raw = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(raw)
vim.api.nvim_buf_set_lines(raw, 0, -1, false, { 'Ruwe bron' })
vim.bo[raw].readonly = true
activity.record(raw, 'Eerst kijken.', vim.log.levels.WARN, { action = 'first' })
activity.record(raw, 'Daarna herstellen.', vim.log.levels.ERROR, { action = 'second' })
wait(function() return #vim.api.nvim_buf_get_extmarks(raw, notices.namespace, 0, -1, {}) == 1 end)
local mark = vim.api.nvim_buf_get_extmarks(raw, notices.namespace, 0, -1, { details = true })[1]
local virtual = {}
for _, row in ipairs(mark[4].virt_lines) do
  for _, chunk in ipairs(row) do virtual[#virtual + 1] = chunk[1] end
end
local text = table.concat(virtual, '\n')
assert(text:find('Eerst kijken.', 1, true) < text:find('Daarna herstellen.', 1, true))
os.date = real_date
print('notice timestamps: OK')
