package.loaded.site_duplicates = nil
local duplicates = require 'site_duplicates'

local command = duplicates._command 'SW'
assert(command[1]:match '/%.venv/bin/python$')
assert(command[2] == '-m')
assert(command[3] == 'texttools.site_duplicates_cli')
assert(command[4] == '--json')
assert(command[6] == 'SW')

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
        },
      },
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
assert(blob:find('/articles/internet/1', 1, true))
assert(blob:find('De Swollenaer: NIET gelezen — timeout', 1, true))

duplicates.setup()
local mapping = vim.fn.maparg('<leader>kd', 'n', false, true)
assert(type(mapping) == 'table' and mapping.desc:find('web', 1, true))

print 'site duplicates: OK'
