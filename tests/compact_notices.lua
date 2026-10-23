local activity = require 'article_activity'
local notices = require 'article_notices'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
local body = { '=== ARTIKEL ===', '', 'Kop', '', 'Melding: Dit is artikeltekst.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend({ 'e: SW', '',
  'Melding: Importbewerking (zonder AI): vaste afkortingen of schrijfwijzen aangepast; witruimte en alineascheiding aangepast.',
  '', }, body))
local function text() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function wait(test) assert(vim.wait(2000, test, 5), text()) end
wait(function() return text():find('Melding: Import opgeschoond (zonder AI).', 1, true) end)
local original = table.concat(notices.content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)), '\n')
local full = 'Bewerkt met Behoudend publicatieklaar maken (<leader>an): minimale redactie. Controleer kop, lead en praktische informatie.'
activity.record(buf, full, vim.log.levels.INFO, { inline = true, notice_key = 'rewrite-method', kind = 'success' })
wait(function() return text():find('Melding: Minimaal geredigeerd (<leader>an).', 1, true) end)
assert(activity.snapshot(buf).entries[1].message == full, 'volledige historie ingekort')
local error = 'Datumcontrole mislukt; er is niets verzonden. ' .. string.rep('Gedetailleerde toelichting. ', 20)
activity.record(buf, error, vim.log.levels.ERROR, { action = 'Datumcontrole' })
wait(function() return text():find('Melding: FOUT: Datumcontrole mislukt; er is niets verzonden.', 1, true) end)
assert(text():find('… (<leader>kl)', 1, true), 'details niet bereikbaar')
assert(activity.snapshot(buf).issues.Datumcontrole.message == error, 'controle of details verloren')
for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line:match('^Melding:') then assert(vim.fn.strchars(line) <= 140) end
end
assert(table.concat(notices.content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)), '\n') == original)
local function check_styles()
  local count = 0
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, notices.style_namespace, 0, -1, { details = true })) do
    local line = vim.api.nvim_buf_get_lines(buf, mark[2], mark[2] + 1, false)[1]
    assert(line:match('^Melding:') and mark[2] < 7, 'stijl buiten kopblok')
    local group = mark[4].hl_group
    assert(vim.api.nvim_get_hl(0, { name = group, link = false }).italic ~= true)
    count = count + 1
  end
  assert(count == 3, 'oude en nieuwe meldingen niet gelijk gestileerd')
end
check_styles()
vim.api.nvim_set_hl(0, 'Comment', { italic = true })
vim.api.nvim_exec_autocmds('ColorScheme', {})
check_styles()
activity.record(buf, 'FOUT: Datumcontrole mislukt.', vim.log.levels.ERROR, { action = 'Datumcontrole' })
wait(function() return text():find('Melding: FOUT: Datumcontrole mislukt.\n', 1, true) end)
assert(not text():find('LET OP: FOUT:', 1, true), 'dubbel ernstprefix')
-- Onbekende opgeslagen tekst zonder volledige historie nooit afkappen.
assert(notices.summary(error, false) == error)
assert(notices.summary('Korte melding.', true) == 'Korte melding.')
assert(notices.summary('Herschreven met Persberichten bewerken (<leader>ar), met automatische redactie.', true)
  == 'Herschreven (<leader>ar).')
print('compact notices: OK')
