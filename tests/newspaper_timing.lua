local ai = require 'ai_text'

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'Kop',
  '',
  '**KAMPEN - De expositie opent zaterdag.**',
  '',
  'De rest van het artikel.',
  '',
  '---',
  '',
  '## Kalender',
  '',
  'Titel: Expositie',
  'Datum: 2026-09-12',
})

local first = table.concat({
  '## Kranttijdsversies',
  '',
  '<!-- texttools-newspaper-timing-workspace: 1 -->',
  '',
  '### Kranttijdsversie B — De Brug',
  '<!-- source-sha256: ' .. string.rep('a', 64) .. ' -->',
  '<!-- plan-sha256: ' .. string.rep('b', 64) .. ' -->',
  '<!-- web-date: 2026-09-11 -->',
  '<!-- newspaper-date: 2026-09-15 -->',
  '',
  'Kop na evenement',
  '',
  '**KAMPEN - De expositie heeft zaterdag plaatsgevonden.**',
  '',
  'De rest van het artikel.',
}, '\n')

assert(ai._apply_timing_versions_section(buf, first), 'kranttijdsectie niet toegepast')
local rendered = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(rendered:find('## Kalender', 1, true), 'kalendersectie ging verloren')
assert(rendered:find('## Kranttijdsversies', 1, true), 'kranttijdsectie ontbreekt')
assert(rendered:find('e: B', 1, true), 'controleregel ging verloren')
assert(rendered:find('=== ARTIKEL ===', 1, true), 'artikelgrens ging verloren')

local second = first:gsub('Kop na evenement', 'Nieuwe beoordeelde kop')
assert(ai._apply_timing_versions_section(buf, second), 'kranttijdsectie niet vervangen')
rendered = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
local _, occurrences = rendered:gsub('## Kranttijdsversies', '')
assert(occurrences == 1, 'kranttijdsectie werd dubbel toegevoegd')
assert(rendered:find('Nieuwe beoordeelde kop', 1, true), 'nieuwe versie ontbreekt')

assert(ai._apply_timing_versions_section(buf, nil), 'kranttijdsectie niet verwijderd')
rendered = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(not rendered:find('## Kranttijdsversies', 1, true), 'kranttijdsectie bleef staan')
assert(rendered:find('## Kalender', 1, true), 'kalender verdween bij opruimen')

print 'newspaper timing: OK'
