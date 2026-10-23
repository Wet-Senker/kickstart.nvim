local activity = require 'article_activity'
local notices = require 'article_notices'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function flush() vim.wait(40, function() return false end) end
local function lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function sync() vim.cmd 'let &undolevels = &undolevels' end
local function stable(buf, command)
  sync()
  vim.cmd(command)
  local expected, tick, tree = lines(buf), vim.api.nvim_buf_get_changedtick(buf), vim.fn.undotree()
  flush()
  activity.record(buf, 'Technische notitie.', nil, { detail = true })
  vim.api.nvim_exec_autocmds('BufEnter', { buffer = buf })
  vim.api.nvim_exec_autocmds('VimResized', {})
  flush()
  assert(vim.deep_equal(lines(buf), expected), command .. ': kopblok werd opnieuw geschreven')
  assert(vim.api.nvim_buf_get_changedtick(buf) == tick, command .. ': achtergrond wijzigde changedtick')
  local after = vim.fn.undotree()
  assert(after.seq_cur == tree.seq_cur and after.seq_last == tree.seq_last,
    command .. ': achtergrond maakte een undo-zijtak')
end
local buf = vim.api.nvim_create_buf(true, false)
vim.bo[buf].undolevels = -1
local original = {
  'e: SW', 'Melding: Import opgeschoond (zonder AI).', 'agenda: ja',
  '@John: Graag controleren.', '', '=== ARTIKEL ===', '', 'Kop', '', 'Oorspronkelijke tekst.',
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
vim.bo[buf].undolevels = 1000
vim.api.nvim_set_current_buf(buf)
flush()
local organized = lines(buf)
assert(not vim.deep_equal(organized, original), 'initiële kopindeling ontbreekt')
stable(buf, 'silent normal! u')
assert(vim.deep_equal(lines(buf), original), 'oudste import niet bereikbaar')
stable(buf, 'silent redo')
assert(vim.deep_equal(lines(buf), organized), 'redo herstelt niet dezelfde indeling')
stable(buf, 'silent undo 0')
-- Ook een verborgen bron niet alsnog ordenen via een ander artikel.
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(other)
activity.record(buf, 'Nog een detail.', nil, { detail = true })
flush()
assert(vim.deep_equal(lines(buf), original))
vim.api.nvim_set_current_buf(buf)
flush()
assert(vim.deep_equal(lines(buf), original))

-- Echt nieuw redactiewerk op de oude tak mag de kop weer netjes indelen.
sync()
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: B, SW' })
flush()
assert(table.concat(lines(buf), '\n'):find('e: B, SW\nagenda: ja\n@John: Graag controleren.\n\nMelding:', 1, true))
assert(lines(buf)[#lines(buf)] == 'Oorspronkelijke tekst.')
-- Een nieuw controleresultaat blijft zichtbaar, ook direct na undo.
stable(buf, 'silent undo 0')
activity.record(buf, 'Fotocredit ontbreekt.', vim.log.levels.WARN, { action = 'Foto' })
flush()
assert(table.concat(lines(buf), '\n'):find('Melding: LET OP: Fotocredit ontbreekt.', 1, true))

-- Een ongedaan gemaakte formattering mag een nog aanwezige beheerde melding
-- niet verdubbelen wanneer de redacteur daarna een instelling toevoegt.
sync()
activity.record(buf, 'Herschreven met Persberichten bewerken.', nil,
  { inline = true, notice_key = 'rewrite-method', kind = 'success' })
flush()
sync()
local at
for index, line in ipairs(lines(buf)) do if line == '=== ARTIKEL ===' then at = index - 1 end end
vim.api.nvim_buf_set_lines(buf, at, at, false, { 'wijk: Heel Zwolle' })
flush()
stable(buf, 'silent undo')
sync()
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: SW' })
flush()
local count = 0
for _, line in ipairs(lines(buf)) do
  if line == 'Melding: Herschreven (<leader>ar).' then count = count + 1 end
end
assert(count == 1, 'melding verdubbeld na undo en nieuwe bewerking')

-- De echte artikelgeschiedenis blijft bereikbaar, niet alleen de kopindeling.
sync()
local rewritten = lines(buf)
rewritten[#rewritten] = 'Herschreven artikeltekst.'
notices.replace_content(buf, rewritten)
flush()
stable(buf, 'silent undo 0')
assert(vim.deep_equal(lines(buf), original), 'herschrijven blokkeerde oudste import')
stable(buf, 'silent! normal! u')
stable(buf, 'silent earlier 1')
stable(buf, 'silent later 1')
stable(buf, 'silent normal! g-')
stable(buf, 'silent normal! g+')
stable(buf, 'silent undo 0')

-- Undo tijdens een lopende controle mag na taakafronding niet worden ingehaald
-- door een uitgestelde formattering. Nieuwe resultaten blijven wel werken.
activity.start(buf, 'undo-test', 'Controleren')
stable(buf, 'silent redo')
local restored = lines(buf)
activity.finish(buf, 'undo-test')
flush()
assert(vim.deep_equal(lines(buf), restored), 'taakafronding ordende herstelde tekst opnieuw')
activity.record(buf, 'Foto gecontroleerd.', nil, { action = 'Foto', kind = 'success' })
flush()
assert(not table.concat(lines(buf), '\n'):find('Melding: LET OP: Fotocredit ontbreekt.', 1, true))
-- Gewoon typen in de body veroorzaakt geen extra bufferwijziging/rendering.
for index = 1, 10 do
  vim.api.nvim_buf_set_lines(buf, -2, -1, false, { 'Artikeltekst ' .. index .. '.' })
end
local tick = vim.api.nvim_buf_get_changedtick(buf)
flush()
assert(vim.api.nvim_buf_get_changedtick(buf) == tick, 'body-invoer veroorzaakte kopmutaties')
print('notice undo: OK')
