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

local command = ai._temporal_print_command('/tmp/artikel.md', { B = '2026-09-11' }, { 'B' }, false)
assert(not vim.tbl_contains(command, '--allow-past-rewrite'), 'toestemming stond standaard aan')
local allowed_command = ai._temporal_print_command(
  '/tmp/artikel.md',
  { B = '2026-09-11' },
  { 'B' },
  true
)
assert(vim.tbl_contains(allowed_command, '--allow-past-rewrite'), 'toestemming ontbrak na keuze')
local skipped_command = ai._temporal_print_command(
  '/tmp/artikel.md',
  { B = '2026-09-11' },
  { 'B' },
  false,
  true
)
assert(vim.tbl_contains(skipped_command, '--skip-past-newspaper'), 'web-onlykeuze ontbrak')

local deadline_review = {
  signature = 'D:2026-09-27:2026-10-14:1',
  late_editions = { 'D' },
  items = {
    {
      edition = 'D',
      name = 'De Drontenaar',
      content_deadline_week = '39',
      next_publication_date = '2026-10-14',
      next_publication_week = '42',
      too_late = true,
    },
  },
}
local deadline_message = ai._late_newspaper_message(deadline_review)
assert(deadline_message:find('De Drontenaar', 1, true), 'krantnaam ontbreekt')
assert(deadline_message:find('14-10-2026', 1, true), 'krantdatum ontbreekt')
assert(deadline_message:find('week 42', 1, true), 'verschijningsweek ontbreekt')
assert(deadline_message:find('week 39', 1, true), 'inhoudelijke deadline ontbreekt')

local deadline_buf = vim.api.nvim_create_buf(false, true)
local original_confirm = ai._late_newspaper_confirm
ai._late_newspaper_confirm = function() return 1 end
assert(ai._review_late_newspapers(deadline_buf, deadline_review), 'websitekeuze geweigerd')
assert(vim.b[deadline_buf].late_newspaper_decision.mode == 'website', 'websitekeuze niet onthouden')
ai._late_newspaper_confirm = function() error('onthouden keuze vroeg opnieuw') end
assert(ai._review_late_newspapers(deadline_buf, deadline_review), 'onthouden keuze geweigerd')
ai._late_newspaper_confirm = original_confirm

print 'newspaper timing: OK'
