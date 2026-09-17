local ai = require 'ai_text'

assert(
  ai._priority_message({ priority = { value = 4, reason = 'geen concrete plaats' } })
    == 'Krantprioriteit 4 — geen concrete plaats',
  'prioriteitsmelding toont waarde en reden niet'
)
assert(ai._priority_message({}) == nil, 'ontbrekende prioriteit levert toch een melding')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  'prio: 3',
  '',
  '=== ARTIKEL ===',
  '',
  'Kop',
  '',
  'KAMPEN - Tekst.',
})

assert(ai._set_priority_control(buf, 4), 'prioriteitsregel kon niet worden aangepast')
local result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(result:find('prio: 4', 1, true), 'nieuwe prioriteit ontbreekt')
assert(not result:find('prio: 3', 1, true), 'oude prioriteit bleef staan')
assert(result:find('e: B', 1, true), 'andere controleregel ging verloren')
assert(result:find('=== ARTIKEL ===', 1, true), 'artikelgrens ging verloren')

print('priority controls: OK')
