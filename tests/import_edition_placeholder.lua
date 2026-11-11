local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = root
local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = root .. '/activity.json' }
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, root .. '/werk/artikel.md')
local source = { 'e:', 'agenda: nee', '', '=== LOG ===', '[09:09] Import opgeschoond (zonder AI).', '',
  '=== ARTIKEL ===', '', 'Het is maar één papiertje', '', 'Een landelijke campagne tegen zwerfafval.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.fn.writefile(source, vim.api.nvim_buf_get_name(buf))
local native_system = vim.system
local resolves = 0
vim.system = function(command, options, done)
  assert(command[1]:match('pubble%-send$') and vim.tbl_contains(command, '--resolve-editions'),
    'lege editie startte onverwacht AI, media, datumreview of publicatie')
  resolves = resolves + 1
  return native_system(command, options, done)
end
ai._edition_send_confirm = function() error 'lege keuze werd als een te bevestigen default getoond' end
ai._missing_photo_choice = function() error 'fotokeuze vóór editiekeuze' end
ai.pubble_send(buf, true, true)
assert(vim.wait(10000, function()
  local snapshot = activity.snapshot(buf)
  return snapshot and snapshot.attention and snapshot.attention.message:find('Geen editie gekozen', 1, true) ~= nil
end, 10), 'verzending met lege editie gaf geen gerichte melding: ' .. vim.inspect(activity.snapshot(buf))
  .. '; resolves=' .. resolves)
assert(resolves == 1, 'herhaalde resolver of vervolgwerk bij lege editie')
assert(not vim.b[buf].publication_in_progress and not vim.b[buf].publication_planning_pending)
assert(vim.deep_equal(vim.fn.readfile(vim.api.nvim_buf_get_name(buf)), source), 'bronbestand werd gewijzigd')
vim.system = native_system
print('import edition placeholder: OK')
