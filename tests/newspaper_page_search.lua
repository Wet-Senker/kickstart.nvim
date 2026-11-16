package.loaded.newspaper_page_search = nil
local search = require 'newspaper_page_search'

local command = search._command('gemeentenieuws')
assert(command[1]:match '/%.venv/bin/python$')
assert(command[3] == 'texttools.newspaper_page_search_cli')
assert(command[4] == '--json')
assert(command[6] == 'gemeentenieuws')

local lines, ranges = search._render {
  edition = {
    publication = 'De Brug', edition_id = 24676,
    publication_date = '2026-11-17T00:00:00Z',
  },
  assessed_article_count = 2,
  ai_call_count = 1,
  requested_presets = { 'ondernemen', 'gemeentenieuws' },
  preset_labels = {
    ondernemen = 'Ondernemen in Kampen',
    gemeentenieuws = 'Gemeentenieuws',
  },
  candidates = {
    ondernemen = {
      {
        article_id = 101,
        headline = 'Nieuw bedrijf opent in Kampen',
        page_number = 0,
        verdict = 'sterk',
        reason = 'Nieuwe lokale onderneming.',
        evidence = 'Het bedrijf opent dinsdag.',
        editor_url = 'https://editor.test/articles/newspaper/101',
      },
    },
    gemeentenieuws = {
      {
        article_id = 102,
        headline = 'Raad stemt over verkeersplan',
        page_number = 7,
        verdict = 'mogelijk',
        reason = 'Gemeentelijk beleidsbesluit.',
        evidence = 'De raad stemt donderdag.',
        editor_url = 'https://editor.test/articles/newspaper/102',
      },
    },
  },
  detail_failures = { 102 },
}
local blob = table.concat(lines, '\n')
assert(blob:find('De Brug · 2026-11-17', 1, true))
assert(blob:find('2 bericht(en) beoordeeld · 1 AI-ronde(s)', 1, true))
assert(blob:find('Ondernemen in Kampen (1)', 1, true))
assert(blob:find('[sterk] Nieuw bedrijf opent in Kampen — nog niet geplaatst', 1, true))
assert(blob:find('[mogelijk] Raad stemt over verkeersplan — pagina 7', 1, true))
assert(blob:find('kon alleen de kop/zoekmetadata worden beoordeeld', 1, true))
assert(not blob:find('/articles/newspaper/101', 1, true), 'URL hoort alleen in details')

local linked = 0
for _, entry in pairs(ranges) do
  if entry.candidate then linked = linked + 1 end
end
assert(linked == 2, 'beide kandidaatregels moeten bedienbaar zijn')

search.setup()
local mapping = vim.fn.maparg('<leader>ks', 'n', false, true)
assert(type(mapping) == 'table' and type(mapping.callback) == 'function', 'leaderkoppeling ontbreekt')

print 'newspaper page search: OK'
