package.loaded['agenda_bron'] = nil

local module = require 'agenda_bron'

-- Commando-opbouw: venv-python, module, altijd --json, dan de argumenten.
local list_cmd = module._command('bron', 'list')
assert(list_cmd[1]:match '/%.venv/bin/python$')
assert(list_cmd[2] == '-m')
assert(list_cmd[3] == 'texttools.agenda_cli')
assert(list_cmd[4] == '--json')
assert(list_cmd[5] == 'bron')
assert(list_cmd[6] == 'list')

local add_cmd = module._command('bron', 'add', 'https://x.nl/agenda', '--editie', 'B')
assert(add_cmd[6] == 'add')
assert(add_cmd[7] == 'https://x.nl/agenda')
assert(add_cmd[8] == '--editie')
assert(add_cmd[9] == 'B')

-- Leeg overzicht toont een uitnodiging tot toevoegen.
local empty = module._render_lines {}
assert(vim.tbl_contains(empty, 'Geen agendabronnen. Voeg er een toe met :AgendaBronToevoegen'))

-- Gevulde lijst groepeert op status en toont herkomst en plaatsen.
local rendered = module._render_lines {
  {
    id = 1,
    name = 'Cultuur Kampen',
    status = 'active',
    origin = 'manual',
    edition = 'B',
    places = { 'Kampen' },
    canonical_url = 'https://cultuurkampen.nl/agenda',
    last_seen = '2026-09-09T09:00:00+00:00',
  },
  {
    id = 2,
    name = 'Gevonden site',
    status = 'candidate',
    origin = 'search',
    edition = 'B',
    places = {},
    canonical_url = 'https://gevonden.nl/agenda',
    last_seen = '2026-09-09T09:00:00+00:00',
  },
}
local blob = table.concat(rendered, '\n')
assert(blob:find('ACTIEF (1)', 1, true), 'actieve groep ontbreekt')
assert(blob:find('KANDIDAAT (1)', 1, true), 'kandidaatgroep ontbreekt')
assert(blob:find('[1] Cultuur Kampen — handmatig — editie B — Kampen', 1, true), 'actieve regel klopt niet')
assert(blob:find('[2] Gevonden site — zoekronde — editie B — -', 1, true), 'zoekronde-herkomst ontbreekt')
assert(blob:find('https://cultuurkampen.nl/agenda', 1, true), 'canonieke URL ontbreekt')

-- Afgewezen bron toont de reden.
local rejected = module._render_lines {
  {
    id = 3,
    name = 'Nep',
    status = 'rejected',
    origin = 'manual',
    edition = 'B',
    places = {},
    reject_reason = 'geen echte agenda',
    canonical_url = 'https://nep.nl/agenda',
    last_seen = '2026-09-09T09:00:00+00:00',
  },
}
assert(table.concat(rejected, '\n'):find('reden: geen echte agenda', 1, true), 'afwijsreden ontbreekt')

print('agenda_bron: OK')
