local agenda = require 'agenda_page'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function prepared(items)
  local lines = { '---', 'agenda_page:', '  version: 1', '  edition: B', '---', '', '=== AGENDAPAGINA ===', '' }
  for day = 1, 6 do
    lines[#lines + 1] = '## dinsdag ' .. (19 + day) .. ' oktober'
    for item = 1, items / 6 do
      vim.list_extend(lines, { '', '### Concert ' .. item, 'Tijd: 10:00 uur', 'Locatie: Kerk', '', 'Er is een concert.' })
    end
  end
  return lines
end
local function source(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local function messages(buf)
  local state = activity.snapshot(buf)
  local lines = {}
  for _, entry in ipairs(state and state.entries or {}) do lines[#lines + 1] = entry.message end
  return table.concat(lines, '\n')
end
local buf = source(prepared(60))
local other = source { '=== ARTIKEL ===', '', 'Een ander artikel.' }
vim.api.nvim_set_current_buf(other)
local native_system = vim.system
local launches = 0
vim.system = function(cmd, options, done)
  launches = launches + 1
  assert(cmd[3] == 'texttools.agenda_page_cli' and cmd[4] == 'measure', 'Telling startte AI/publicatie')
  return native_system(cmd, options, done)
end
agenda.measure(buf)
assert(vim.wait(10000, function() return vim.b[buf].agenda_page_capacity ~= nil end), 'Telling bleef hangen')
assert(launches == 1, 'Eén telling startte meerdere processen')
assert(vim.b[buf].agenda_page_capacity.paragraphs == 245
  and vim.b[buf].agenda_page_capacity.remove_items_estimate == 20, 'Echte coretelling klopt niet')
assert(messages(buf):find('Verwijder nog ongeveer 20', 1, true), 'Verwijderadvies ontbreekt in logboek')
assert(not messages(other):find('alinea', 1, true), 'Advies belandde bij een ander artikel')
assert(vim.deep_equal(require('article_notices').content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
  require('article_notices').content_lines(prepared(60))),
  'Meten wijzigde de agendatekst')
agenda.measure(buf, { automatic = true })
assert(launches == 1, 'Automatische telling herhaalde dezelfde revisie')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, prepared(36))
agenda.measure(buf)
assert(vim.wait(10000, function() return vim.b[buf].agenda_page_capacity.items == 36 end), 'Hertelling bleef hangen')
assert(launches == 2 and vim.b[buf].agenda_page_capacity.remove_items_estimate == 0)
assert(not activity.snapshot(buf).issues['Agenda · Omvang'], 'Passende agenda liet oude overschrijding staan')
assert(messages(buf):find('Past globaal', 1, true), 'Passende agenda mist bevestiging')

-- Late telling mag geen oude cijfers tonen of nieuwere tekst vervangen.
local replies = {}
vim.system = function(cmd, _, done)
  launches = launches + 1
  assert(cmd[4] == 'measure')
  replies[#replies + 1] = done
  return {}
end
local payload = vim.json.encode {
  version = 1, paragraphs = 245, items = 60, capacity = 166,
  over_by = 79, remove_items_estimate = 20, message = 'OUD RESULTAAT',
}
agenda.measure(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere tekst.' })
replies[#replies] { code = 0, stdout = payload }
vim.wait(100, function() return false end)
assert(not messages(buf):find('OUD RESULTAAT', 1, true), 'Verouderde telling werd getoond')
assert(vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] == 'Nieuwere tekst.')

-- Ontbrekende/ongeldige uitvoer wordt geen valse "past" en blokkeert retry niet.
agenda.measure(buf)
replies[#replies] { code = 0, stdout = '{}' }
assert(vim.wait(1000, function() return messages(buf):find('Agendatelling mislukt', 1, true) end))
vim.system = function() error('Bewuste startfout') end
agenda.measure(buf)
vim.wait(100, function() return false end)
vim.system = native_system
agenda.measure(buf)
assert(vim.wait(10000, function()
  return vim.b[buf].agenda_page_measure_fingerprint == vim.fn.sha256(table.concat(
    require('article_notices').content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)), '\n'))
end), 'Startfout hield een volgende telling vast')

-- De importroute gebruikt dezelfde read-only actie, ook vóór <leader>ka.
local raw = source { 'dinsdag 20 oktober', '', 'Concert', '', '10.00 uur | Kerk', '', 'Concerttekst.', '',
  'woensdag 21 oktober', '', 'Markt', '', '12.00 uur | Plein', '', 'Markttekst.' }
require('ai_text')._article_autodetect(raw)
assert(vim.wait(10000, function() return vim.b[raw].agenda_page_capacity ~= nil end), 'Import mist automatische telling')
assert(vim.b[raw].agenda_page_capacity.source_format == 'raw', 'Importtelling werd niet voorlopig genoemd')
assert(vim.b[raw].agenda_page_capacity.items == 2)

-- Na voorbereiding wordt de gewijzigde, voorbereide tekst opnieuw geteld;
-- een eventueel nog lopende ruwe telling kan die uitkomst niet vervangen.
local prepare_buf = source(vim.api.nvim_buf_get_lines(raw, 0, -1, false))
vim.system = function(cmd, options, done)
  if cmd[4] == 'measure' then return native_system(cmd, options, done) end
  assert(cmd[4] == 'prepare', 'Voorbereiding startte onverwachte actie')
  done { code = 0, stdout = table.concat(prepared(36), '\n') }
  return { is_closing = function() return false end }
end
agenda.prepare(prepare_buf)
assert(vim.wait(10000, function()
  local data = vim.b[prepare_buf].agenda_page_capacity
  return data and data.source_format == 'prepared' and data.items == 36
end), 'Voorbereide tekst kreeg geen eigen automatische telling')
assert(not activity.snapshot(prepare_buf).attention,
  'Een oude voorbereidingsinstructie verbergt de passende omvangmelding')

-- Sluiten tijdens het tellen mag geen advies in de huidige buffer plaatsen.
local closed = source(prepared(60))
local reply
vim.system = function(_, _, done) reply = done; return {} end
agenda.measure(closed)
vim.api.nvim_buf_delete(closed, { force = true })
reply { code = 0, stdout = payload }
vim.wait(100, function() return false end)
assert(not messages(other):find('OUD RESULTAAT', 1, true), 'Gesloten bron vervuilde ander artikel')
vim.system = native_system
agenda.setup()
assert(vim.fn.exists ':AgendaPaginaOmvang' == 2)
assert(vim.fn.maparg('<leader>km', 'n', false, true).desc == '[K]rant agendapagina [m]eten (zonder AI)')
print 'agenda page capacity: OK'
