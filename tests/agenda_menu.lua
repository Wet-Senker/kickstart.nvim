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

local weekend_cmd = module._command('weekendbericht', '--editie', 'all')
assert(weekend_cmd[5] == 'weekendbericht')
assert(weekend_cmd[6] == '--editie')
assert(weekend_cmd[7] == 'all')

local scan_cmd = module._command('website-scan', '--editie', 'all')
assert(scan_cmd[5] == 'website-scan')
assert(scan_cmd[7] == 'all')

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

-- Eigen-doublures-render: meerdere edities in één run, met bewerk-URL's en
-- een leesfout per editie.
local pair_lines = module._render_pairs {
  van = '2026-09-10', tot = '2026-10-22',
  edities = {
    { editie = 'B', aantal_items = 104, fout = vim.NIL, paren = {} },
    { editie = 'SW', aantal_items = 134, fout = vim.NIL, paren = {
      { left = { title = 'Nazomer Fair', date = '2026-09-11', editor_url = 'https://brugmedia.pubble.dev/articles/internet/a1' },
        right = { title = 'Nazomer Fair Het 8ste Werk', editor_url = 'https://brugmedia.pubble.dev/articles/internet/a2' },
        reason = 'zelfde datum; zelfde locatie en gelijkende titel', score = 88 },
    } },
    { editie = 'ST', aantal_items = 0, fout = 'Kan Pubble niet bereiken', paren = {} },
  },
}
local pblob = table.concat(pair_lines, '\n')
assert(pblob:find('Editie B: 104 item', 1, true), 'editie B-regel ontbreekt')
assert(pblob:find('Editie SW: 134 item', 1, true), 'editie SW-regel ontbreekt')
assert(pblob:find('/articles/internet/a1', 1, true), 'bewerk-URL links ontbreekt')
assert(pblob:find('Editie ST: NIET gelezen', 1, true), 'leesfout-regel ontbreekt')

local website_lines, website_by_line = module._render_website_candidates {
  date_from = '2026-08-23', date_to = '2026-09-13',
  results = {
    { edition = 'B', scanned = 120, details_checked = 14, error = vim.NIL,
      candidates = {
        { edition = 'B', article_id = 321, headline = 'Concert in Kampen',
          display_date = '2026-09-10T10:00:00+02:00', score = 11,
          editor_url = 'https://brugmedia.pubble.dev/articles/internet/321' },
      } },
    { edition = 'D', scanned = 0, details_checked = 0, error = 'timeout', candidates = {} },
  },
}
local wblob = table.concat(website_lines, '\n')
assert(wblob:find('Concert in Kampen — score 11', 1, true), 'websitekandidaat ontbreekt')
assert(wblob:find('Editie D: NIET gelezen', 1, true), 'websiteleesfout ontbreekt')
local mapped
for _, candidate in pairs(website_by_line) do mapped = candidate end
assert(mapped and mapped.article_id == 321, 'artikelregel is niet selecteerbaar')

-- Regels met een ingebedde newline (rommelige Pubble-titel) worden platgeslagen,
-- anders weigert nvim_buf_set_lines ze.
local sanitized = module._sanitize_lines { 'Alzheimer Café\nZwolle', 'gewoon' }
assert(sanitized[1] == 'Alzheimer Café Zwolle', 'newline niet platgeslagen')
assert(not sanitized[1]:find('\n', 1, true), 'er zit nog een newline in')

print('agenda_menu: OK')
