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

local reject_cmd = module._command('website-afwijzen', '--editie', 'D', '--artikel-id', '321')
assert(reject_cmd[5] == 'website-afwijzen')
assert(reject_cmd[7] == 'D')
assert(reject_cmd[9] == '321')

local article_publish_cmd = module._command('artikel-plaatsen', '/tmp/artikel.md', '--write')
assert(article_publish_cmd[5] == 'artikel-plaatsen')
assert(article_publish_cmd[6] == '/tmp/artikel.md')
assert(article_publish_cmd[7] == '--write')
module.setup()
local article_publish_map = vim.fn.maparg('<leader>kA', 'n', false, true)
assert(type(article_publish_map) == 'table' and article_publish_map.desc:find('alleen', 1, true),
  'globale leader voor alleen agenda ontbreekt')

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
      { left = { title = 'Nazomer Fair', date = '2026-09-11', editor_url = 'https://brugmedia.pubble.nl/articles/internet/a1' },
        right = { title = 'Nazomer Fair Het 8ste Werk', editor_url = 'https://brugmedia.pubble.nl/articles/internet/a2' },
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
    { edition = 'B', scanned = 120, details_checked = 14, rejected_hidden_count = 2, error = vim.NIL,
      candidates = {
        { edition = 'B', article_id = 321, headline = 'Concert in Kampen',
          display_date = '2026-09-10T10:00:00+02:00', score = 11,
          editor_url = 'https://brugmedia.pubble.nl/articles/internet/321' },
      } },
    { edition = 'D', scanned = 0, details_checked = 0, error = 'timeout', candidates = {} },
  },
}
local wblob = table.concat(website_lines, '\n')
assert(wblob:find('Concert in Kampen — score 11', 1, true), 'websitekandidaat ontbreekt')
assert(wblob:find('2 afgewezen verborgen', 1, true), 'afgewezen aantal ontbreekt')
assert(wblob:find('x: geen agenda nodig', 1, true), 'afwijsbediening ontbreekt')
assert(wblob:find('Editie D: NIET gelezen', 1, true), 'websiteleesfout ontbreekt')
local mapped
for _, candidate in pairs(website_by_line) do mapped = candidate end
assert(mapped and mapped.article_id == 321, 'artikelregel is niet selecteerbaar')

local scan_help = module._website_scan_help()
assert(vim.inspect(scan_help):find('Enter', 1, true), 'agenda-scanhulp mist voorstelroute')
local proposal_buf = vim.api.nvim_create_buf(false, true)
local proposal_help = module._website_proposal_help(proposal_buf)
assert(vim.inspect(proposal_help):find('<leader>kA', 1, true), 'agenda-voorstel mist plaatsingsstap')
vim.b[proposal_buf].website_agenda_status = 'partial'
local recovery_help = module._website_proposal_help(proposal_buf)
assert(recovery_help.status:find('herstelmarkeringen', 1, true), 'gedeeltelijke agenda-plaatsing mist hersteladvies')

-- Regels met een ingebedde newline (rommelige Pubble-titel) worden platgeslagen,
-- anders weigert nvim_buf_set_lines ze.
local sanitized = module._sanitize_lines { 'Alzheimer Café\nZwolle', 'gewoon' }
assert(sanitized[1] == 'Alzheimer Café Zwolle', 'newline niet platgeslagen')
assert(not sanitized[1]:find('\n', 1, true), 'er zit nog een newline in')

-- Een weekendbatch blijft zichtbaar als losse buffers, maar wordt vlak voor
-- publicatie deterministisch samengevoegd uit de actuele (bewerkte) inhoud.
local function weekend_doc(code, place, title)
  return table.concat({
    '---',
    'newspaper:',
    '  editions: ' .. code,
    '  newspaper_article_ids:',
    '    ' .. code .. ': null',
    '  article_join_id: null',
    '  skip_editions: [' .. code .. ']',
    '  working_title: "38 - Weekendtips ' .. place .. '"',
    'web:',
    '  internet_article_ids:',
    '    ' .. code .. ': null',
    'calendar_disabled: true',
    'media:',
    '  editorial_asset: weekend-overview',
    '---',
    '',
    'e: ' .. code,
    'agenda: nee',
    '',
    '=== ARTIKEL ===',
    '',
    '# ' .. title,
    '',
    '**' .. place:upper() .. ' - Lead.**',
  }, '\n')
end

local batch_a = vim.api.nvim_create_buf(false, true)
local batch_b = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(batch_a, 0, -1, false, vim.split(weekend_doc('B', 'Kampen', 'Bewerkte Kamper kop'), '\n'))
vim.api.nvim_buf_set_lines(batch_b, 0, -1, false, vim.split(weekend_doc('SW', 'Zwolle', 'Bewerkte Zwolse kop'), '\n'))
vim.b[batch_a].weekend_batch_id = 'headless-test'
vim.b[batch_b].weekend_batch_id = 'headless-test'
module._weekend_batches['headless-test'] = {
  id = 'headless-test',
  sources = {
    { buf = batch_a, edition = 'B' },
    { buf = batch_b, edition = 'SW' },
  },
  now = '2026-09-18T10:00:00+02:00',
  preparing = false,
  sent = false,
}
local success_hook
package.loaded['ai_text'] = {
  set_publication_success_hook = function(_, callback) success_hook = callback end,
}
local controller
assert(module.prepare_weekend_batch_send(batch_a, function(buf) controller = buf end), 'batch niet herkend')
assert(vim.wait(5000, function() return controller ~= nil end, 10), 'batchcontroller niet gemaakt')
local combined = table.concat(vim.api.nvim_buf_get_lines(controller, 0, -1, false), '\n')
assert(combined:find('Bewerkte Kamper kop', 1, true), 'actuele Kamper buffertekst ontbreekt')
assert(combined:find('Bewerkte Zwolse kop', 1, true), 'actuele Zwolse buffertekst ontbreekt')
assert(type(success_hook) == 'function', 'batch heeft geen succesafhandeling geregistreerd')
success_hook()
assert(vim.b[batch_a].weekend_batch_sent == true, 'eerste bronbuffer niet als gepubliceerd gemarkeerd')
assert(vim.b[batch_b].weekend_batch_sent == true, 'tweede bronbuffer niet als gepubliceerd gemarkeerd')
assert(vim.bo[batch_a].modifiable == false and vim.bo[batch_b].modifiable == false,
  'gepubliceerde weekendbuffers zijn nog wijzigbaar')

print('agenda_menu: OK')
