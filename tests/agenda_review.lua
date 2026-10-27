-- Bestaande printagenda: expliciet verversen zonder AI, met late-callbackbescherming.
local agenda = require 'agenda_page'
local notices = require 'texttools_notify'
local system, measure, notify = vim.system, agenda.measure, notices.notify
local pending, mode, sent, messages = nil, 'review', false, {}
local last_options
agenda.measure = function() end
notices.notify = function(message, _, options) last_options = options; table.insert(messages, message) end
vim.system = function(command, options, done)
  if mode == 'review' then
    assert(command[4] == 'review', 'bestaande agenda startte opnieuw AI-voorbereiding')
    assert(options.stdin:find('=== AGENDAPAGINA ===', 1, true))
    pending = done
  elseif command[4] == 'validate' then
    pending = done
  else
    sent = true
    error('onjuiste verzendactie: ' .. table.concat(command, ' '))
  end
  return { is_closing = function() return false end }
end

local source = {
  '=== AGENDAPAGINA ===', '', '## vrijdag 30 oktober', '',
  '### Roll On bij Quintus', 'Tijd: 18:30 uur', 'Locatie: ONTBREEKT: locatie', '',
  'Jongeren kunnen rolschaatsen.',
}
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
agenda.prepare(buf)
assert(pending, 'geen expliciete markeringsactie gestart')
local reply = table.concat(source, '\n'):gsub('Tijd:', 'Controle: ⚠ locatie ontbreekt — vul de locatie in\nTijd:')
pending { code = 0, stdout = reply }
assert(vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Controle:', 1, true)
end))
-- De uitleg is een echte bufferregel: dd mag haar verwijderen.
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
for index, line in ipairs(lines) do
  if line:match '^Controle:' then
    vim.api.nvim_win_set_cursor(0, { index, 0 })
    vim.cmd 'normal! dd'
    break
  end
end
assert(not table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Controle:', 1, true))

-- Een laat reviewresultaat mag nieuwe bewerkingen niet overschrijven.
agenda.prepare(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Mijn nieuwe tekst.' })
pending { code = 0, stdout = reply }
vim.wait(100, function() return false end)
assert(vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] == 'Mijn nieuwe tekst.')

-- Een verouderde validatie mag evenmin als geldige verzendcontrole tellen.
mode = 'validate'
agenda.validate(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nog een wijziging.' })
pending { code = 0, stdout = '{"valid":true,"errors":[]}' }
vim.wait(100, function() return false end)
assert(vim.b[buf].agenda_page_validation == nil)

-- De exacte Python-foutmelding bereikt de gebruiker ongewijzigd.
agenda.validate(buf)
pending { code = 1, stdout = vim.json.encode {
  valid = false,
  errors = {
    "'Roll On bij Quintus': tekst ontbreekt — voeg een beschrijving toe (vrijdag 30 oktober, 18:30 uur)",
    'TWEEDE UITGEBREIDE FOUTDETAIL',
  },
  summary = "Niet verzendklaar: 'Roll On bij Quintus': tekst ontbreekt (+1 ander aandachtspunt)",
} }
assert(vim.wait(1000, function()
  return vim.inspect(messages):find('Roll On bij Quintus', 1, true)
end))
local shortened = require('article_notices').summary(messages[#messages], true)
assert(shortened:find('Roll On bij Quintus', 1, true), 'compacte melding verbergt de itemtitel')
assert(not messages[#messages]:find('TWEEDE UITGEBREIDE', 1, true), 'alle foutdetails werden opnieuw bovenaan getoond')
assert(vim.b[buf].agenda_page_validation.errors[2] == 'TWEEDE UITGEBREIDE FOUTDETAIL', 'uitgebreide diagnose ging verloren')
assert(last_options.buf == buf and last_options.action == 'Agenda · Controle', 'controlerapport mist stabiele bron/actie')
local select = vim.ui.select
vim.ui.select = function(items, _, done) done(items[1]) end
agenda.send(buf)
pending { code = 1, stdout = vim.json.encode {
  valid = false, errors = { 'Volledige foutdetails.' },
  summary = "Niet verzendklaar: 'Roll On bij Quintus': tekst ontbreekt",
} }
assert(vim.wait(1000, function() return messages[#messages]:match '^Niet verzonden:' end))
vim.ui.select = select
assert(not sent, 'ongeldige controle publiceerde toch')
vim.system, agenda.measure, notices.notify = system, measure, notify
print 'agenda item review: OK'
