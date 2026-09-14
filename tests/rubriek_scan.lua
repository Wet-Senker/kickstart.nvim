package.loaded.rubriek_scan = nil
local scan = require 'rubriek_scan'

local command = scan._command('SW', true)
assert(command[1]:match '/%.venv/bin/python$')
assert(command[3] == 'texttools.rubriek_scan_cli')
assert(command[4] == '--json')
assert(command[6] == 'SW')
assert(command[7] == '--include-reviewed')
assert(scan._mark_command()[5] == '--mark-reviewed')

local lines, ranges = scan._render {
  from = '2026-09-01',
  to = '2026-09-14',
  sites = {
    {
      edition = 'B',
      publication = 'De Brug',
      article_count = 20,
      error = vim.NIL,
      candidates = {
        {
          article_id = 101,
          headline = 'Go-ahead wint bekerduel van DOS',
          display_date_label = '2026-09-12',
          current_category_name = 'Algemeen',
          current_category_id = 1,
          suggested_rubriek = 'sport',
          suggested_category_name = 'Sport',
          suggested_category_id = 2,
          score = 12,
          matched = { 'bekerduel', 'competitie' },
          editor_url = 'https://editor.test/articles/internet/101',
          lead = 'De competitie begint volgende week.',
          review_key = ('a'):rep(64),
          reviewed = false,
        },
      },
      reviewed_hidden_count = 3,
    },
    {
      edition = 'SW',
      publication = 'De Swollenaer',
      article_count = 0,
      candidates = {},
      error = 'timeout',
    },
  },
}
local blob = table.concat(lines, '\n')
assert(blob:find('De Brug: 20 artikel(en), 1 voorstel', 1, true))
assert(blob:find('nu: Algemeen → Sport (score 12)', 1, true))
assert(blob:find('3 afgehandelde kandidaat(en) verborgen', 1, true))
assert(blob:find('m = afgehandeld', 1, true))
assert(blob:find('De Swollenaer: NIET gelezen — timeout', 1, true))
assert(not blob:find('/articles/internet/101', 1, true), 'editor-URL hoort niet in het overzicht')

local linked = false
for _, entry in pairs(ranges) do
  if entry.candidate and entry.candidate.article_id == 101 then
    linked = true
    assert(entry.candidate.review_key == ('a'):rep(64), 'kandidaat mist review_key voor markeren')
  end
end
assert(linked, 'artikelregel is niet aan zijn kandidaat gekoppeld')

scan.setup()
local mapping = vim.fn.maparg('<leader>kr', 'n', false, true)
assert(type(mapping) == 'table' and type(mapping.callback) == 'function', 'leaderkoppeling ontbreekt')

print 'rubriek scan: OK'
