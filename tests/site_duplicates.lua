package.loaded.site_duplicates = nil
local duplicates = require 'site_duplicates'

local command = duplicates._command 'SW'
assert(command[1]:match '/%.venv/bin/python$')
assert(command[2] == '-m')
assert(command[3] == 'texttools.site_duplicates_cli')
assert(command[4] == '--json')
assert(command[6] == 'SW')
local reviewed_command = duplicates._command('SW', true)
assert(reviewed_command[7] == '--include-reviewed')
local mark_command = duplicates._mark_command()
assert(mark_command[4] == '--json')
assert(mark_command[5] == '--mark-reviewed')

local lines = duplicates._render {
  from = '2026-09-01',
  to = '2026-09-14',
  max_days_apart = 7,
  sites = {
    {
      edition = 'B',
      publication = 'De Brug',
      article_count = 31,
      error = vim.NIL,
      pairs = {
        {
          left = {
            headline = 'Dezelfde aankondiging',
            display_date_label = '01-09-2026',
            editor_url = 'https://editor.test/articles/internet/1',
          },
          right = {
            headline = 'Anders geschreven aankondiging',
            display_date_label = '05-09-2026',
            editor_url = 'https://editor.test/articles/internet/2',
          },
          reason = 'sterk gelijkende inhoud',
          days_apart = 4,
          score = 86,
          review_key = 'abc',
          reviewed = true,
        },
      },
      reviewed_hidden_count = 2,
      truncated = false,
      detail_errors = 0,
    },
    {
      edition = 'SW',
      publication = 'De Swollenaer',
      article_count = 0,
      pairs = {},
      error = 'timeout',
    },
  },
}
local blob = table.concat(lines, '\n')
assert(blob:find('De Brug: 31 actieve artikelen', 1, true))
assert(blob:find('4 dag(en) uiteen (86%)', 1, true))
assert(blob:find('[gecontroleerd] Dezelfde aankondiging', 1, true))
assert(blob:find('2 eerder gecontroleerde kandidaatpaar(en) verborgen', 1, true))
assert(blob:find('<leader>km = getoonde lichting markeren', 1, true))
assert(blob:find('/articles/internet/1', 1, true))
assert(blob:find('De Swollenaer: NIET gelezen — timeout', 1, true))
local keys = duplicates._review_keys {
  sites = { { pairs = { { review_key = 'first' }, { review_key = 'second' } } } },
}
assert(vim.deep_equal(keys, { 'first', 'second' }))

duplicates.setup()
local mapping = vim.fn.maparg('<leader>kd', 'n', false, true)
assert(type(mapping) == 'table' and mapping.desc:find('web', 1, true))

print 'site duplicates: OK'
