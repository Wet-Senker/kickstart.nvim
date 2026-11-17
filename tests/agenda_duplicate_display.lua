local display = require 'agenda_duplicate_display'
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B', '=== ARTIKEL ===', '', 'Kop', '', '## Kalender', '', 'Titel: Zangdienst',
  '', '## Facebook', '', 'Bericht',
})
vim.wo.foldmethod = 'manual'
vim.wo.foldenable = true
display.show(buf, true)
local ns = vim.api.nvim_get_namespaces().AgendaDuplicateDisplay
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
assert(#marks == 1 and marks[1][2] == 1 and marks[1][4].virt_lines_above)
assert(vim.fn.foldclosed(6) == 6 and vim.fn.foldclosedend(6) == 9)
assert(vim.fn.foldlevel(10) == 0, 'Facebook werd meegevouwen')
display.show(buf, false)
assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0)
assert(vim.fn.foldlevel(6) == 0, 'Kalender bleef gevouwen na gedeeltelijke uitsluiting')
