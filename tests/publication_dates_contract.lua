-- Echte Neovim → Python-overdracht. Alleen de uiteindelijke gebruikerskeuze
-- wordt hier bediend; geen nagebootst resultaat van de datumcontrole.
local dates = require('publication_dates')
local dialog = require('user_dialog')
local activity = require('article_activity')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local native_system = vim.system
local calls, menus = {}, {}
vim.system = function(command, options, done)
  assert(command[3] == 'texttools.publication_dates_cli', 'onverwacht extern proces')
  calls[#calls + 1] = vim.deepcopy(command)
  return native_system(command, options, done)
end
dialog.select = function(items, options, done)
  menus[#menus + 1] = { items = items, options = options, done = done }
end
local function wait(test)
  assert(vim.wait(10000, test, 5), 'echte datumcontrole bleef hangen')
end
local function source(body)
  local file = vim.fn.tempname() .. '.md'
  local lines = { 'e: SW', '', '=== ARTIKEL ===', '', 'Een artikelkop', '', 'ZWOLLE - ' .. body }
  vim.fn.writefile(lines, file)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf, file
end
local function start(buf, file, codes, values)
  local result = {}
  dates.review(buf, file, codes, values, function(action, transition)
    result.action, result.transition = action, transition
  end)
  return result
end
local function encoded_dates(command)
  for index, value in ipairs(command) do
    if value == '--display-dates' then return command[index + 1] end
  end
  error('datummapping ontbreekt')
end
local cases = {
  { codes = { 'SW' }, values = {}, encoded = '{}' },
  { codes = { 'B', 'SW', 'ST', 'K' }, values = {}, encoded = '{}' },
  { codes = { 'SW' }, encoded = '{}' },
  { codes = { 'SW' }, values = vim.empty_dict(), encoded = '{}' },
  { codes = { 'SW' }, values = { SW = 'direct' } },
  { codes = { 'B', 'SW', 'ST', 'K' }, values = { SW = '2099-10-21:0', B = 'direct' } },
  { codes = { 'SW' }, values = { SW = '2099-10-21T23:30:00Z' } },
}
for _, case in ipairs(cases) do
  local buf, file = source('Een nieuw raadslid wordt maandag 26 oktober geïnstalleerd.')
  local before, before_calls = vim.api.nvim_buf_get_lines(buf, 0, -1, false), #calls
  local result = start(buf, file, case.codes, case.values)
  wait(function() return result.action ~= nil end)
  assert(result.action == 'ready' and not vim.b[buf].publication_date_review_pending,
    'directe of geplande datum blokkeerde een geldig artikel')
  assert(#calls == before_calls + 1 and #menus == 0, 'onnodige herpoging/gebruikersvraag')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), before))
  local encoded = encoded_dates(calls[#calls])
  if case.encoded then assert(encoded == case.encoded, 'lege mapping werd een JSON-lijst')
  else assert(vim.deep_equal(vim.json.decode(encoded), case.values)) end
end

-- Ook na een fout blijft een bewuste retry werken. Niet-lege lijsten/null-
-- waarden blijven juist fouten: geen algemene versoepeling van de controle.
local buf, file = source('De aangekondigde ov-staking op donderdag 22 oktober gaat niet door.')
for _, invalid in ipairs({ { '2026-10-21' }, { SW = vim.NIL }, { SW = 42 } }) do
  local result = start(buf, file, { 'SW' }, invalid)
  wait(function() return result.action ~= nil end)
  assert(result.action == 'cancel' and not vim.b[buf].publication_date_review_pending)
  local entries = activity.snapshot(buf).entries
  assert(entries[#entries].message:find('publicatiedatums zijn ongeldig', 1, true))
end
local retry = start(buf, file, { 'SW' }, {})
wait(function() return retry.action ~= nil end)
assert(retry.action == 'ready' and #menus == 0)

-- Direct plaatsen slaat een echte inhoudelijke datumvraag NIET over.
buf, file = source('Vandaag gaat de eerder aangekondigde staking niet door.')
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Niet voor publicatie', '> Interne redactienotitie' })
local before_calls = #calls
local result = start(buf, file, { 'B', 'SW', 'ST', 'K' }, {})
wait(function() return #menus == 1 end)
assert(not result.action and menus[1].items[1]:find('Gecontroleerd', 1, true))
menus[1].done(menus[1].items[1])
wait(function() return result.action ~= nil end)
assert(result.action == 'ready' and result.transition and #calls == before_calls + 2)
assert(encoded_dates(calls[#calls]) == '{}', 'bevestiging verloor de datummapping')
local editor = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
local publication = table.concat(vim.fn.readfile(file), '\n')
assert(editor:find('date_approval', 1, true) and editor:find('Interne redactienotitie', 1, true))
assert(publication:find('date_approval', 1, true) and not publication:find('Interne redactienotitie', 1, true))
local cached = start(buf, file, { 'B', 'SW', 'ST', 'K' }, {})
wait(function() return cached.action ~= nil end)
assert(cached.action == 'ready' and #menus == 1, 'geldig akkoord werd opnieuw gevraagd')

-- Een harde datumfout mag ook met direct plaatsen niet blind bevestigd worden.
buf, file = source('De organisatie brengt op 1 januari 2000 een album uit.')
result = start(buf, file, { 'SW' }, {})
wait(function() return #menus == 2 end)
assert(menus[2].items[1] == 'Publicatiedatum aanpassen')
menus[2].done('Tekst zelf aanpassen')
wait(function() return result.action ~= nil end)
assert(result.action == 'edit')

-- Veilige, chat-leesbare foutdiagnose; geen artikeltekst of vrije stderr.
local log = table.concat(vim.fn.readfile(require('workflow_log').log_path()), '\n')
assert(log:find('invalid_display_dates', 1, true) and log:find('"failed"', 1, true))
assert(not log:find('Interne redactienotitie', 1, true))

-- Figuurlijk vandaag/morgen is geen publicatiedatum. Dezelfde column met een
-- echte afspraak voor morgen vraagt nog steeds de gewone expliciete controle.
local column = 'De problemen van vandaag mogen de kansen van morgen niet verdringen. '
  .. 'Het gaat om keuzes die we vandaag durven te maken.'
buf, file = source(column)
local menu_count, call_count = #menus, #calls
result = start(buf, file, { 'B', 'SW', 'ST', 'K', 'D', 'Z' }, {})
wait(function() return result.action ~= nil end)
assert(result.action == 'ready' and #menus == menu_count and #calls == call_count + 1)
buf, file = source(column .. ' Morgen komt de raad bijeen.')
result = start(buf, file, { 'B', 'SW' }, {})
wait(function() return #menus == menu_count + 1 end)
local question = menus[#menus]
assert(question.options.prompt:find('‘morgen’', 1, true))
assert(not question.options.prompt:find('‘vandaag’', 1, true), 'figuurlijk woord toch als datum gevraagd')
assert(question.items[1]:find('Gecontroleerd', 1, true))
question.done(question.items[1])
wait(function() return result.action ~= nil end)
assert(result.action == 'ready')
vim.system = native_system
print('publication dates contract: OK')
