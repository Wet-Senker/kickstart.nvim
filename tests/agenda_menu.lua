package.loaded['agenda_menu'] = nil

local module = require 'agenda_menu'

-- Commando-opbouw: venv-python, module, altijd --json.
local cmd = module._command('import', '--editie', 'B', '--normaliseer')
assert(cmd[1]:match '/%.venv/bin/python$')
assert(cmd[2] == '-m')
assert(cmd[3] == 'texttools.agenda_cli')
assert(cmd[4] == '--json')
assert(cmd[5] == 'import')
assert(cmd[8] == '--normaliseer')

-- Import-render: controle, doublures, nieuw, normalisatie.
local import_lines = module._render_import {
  read_incomplete = false,
  validation = {
    { ref = 'event-1', title = 'Nazomer Fair', ok = true, missing = {}, problems = {} },
    { ref = 'event-2', title = 'Concert', ok = false, missing = { 'Stad' }, problems = {} },
  },
  candidates = {
    { left = { ref = 'event-1', title = 'Nazomer Fair', date = '2026-09-11' },
      right = { title = 'Nazomer Fair' }, reason = 'zelfde datum; sterk gelijkende titel', score = 92 },
  },
  clean = { { ref = 'event-2', title = 'Concert', date = '2026-09-13' } },
  normalized = { { ref = 'event-1', title = 'Nazomer Fair', normalized = 'Opgeschoonde tekst.', error = nil } },
}
local blob = table.concat(import_lines, '\n')
assert(blob:find('✓ [event-1] Nazomer Fair', 1, true), 'geldig item ontbreekt')
assert(blob:find('✗ [event-2] Concert — ontbreekt: Stad', 1, true), 'ontbrekend veld niet getoond')
assert(blob:find('Mogelijke doublures (1)', 1, true), 'doublures ontbreken')
assert(blob:find('Opgeschoonde tekst.', 1, true), 'genormaliseerde tekst ontbreekt')

-- Eigen-doublures-render met bewerk-URL's.
local pair_lines = module._render_pairs {
  editie = 'B', van = '2026-09-10', tot = '2026-10-22', aantal_items = 105,
  paren = {
    { left = { title = 'Nazomer Fair', date = '2026-09-11', editor_url = 'https://brugmedia.pubble.dev/articles/internet/a1' },
      right = { title = 'Nazomer Fair Het 8ste Werk', editor_url = 'https://brugmedia.pubble.dev/articles/internet/a2' },
      reason = 'zelfde datum; zelfde locatie en gelijkende titel', score = 88 },
  },
}
local pblob = table.concat(pair_lines, '\n')
assert(pblob:find('editie B', 1, true), 'editie ontbreekt in kop')
assert(pblob:find('/articles/internet/a1', 1, true), 'bewerk-URL links ontbreekt')
assert(pblob:find('/articles/internet/a2', 1, true), 'bewerk-URL rechts ontbreekt')

print('agenda_menu: OK')
