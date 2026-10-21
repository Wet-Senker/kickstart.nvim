local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local body = 'Eerste bericht\n\nKAMPEN - Eerste nieuws.\n\nTweede bericht\n\nZWOLLE - Ander nieuws.'
local function warnings(buf)
  local found = {}
  local snapshot = activity.snapshot(buf)
  for _, entry in ipairs(snapshot and snapshot.entries or {}) do
    if entry.level >= vim.log.levels.WARN then found[#found + 1] = entry end
  end
  return found
end
local function source(text)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false,
    vim.split('=== ARTIKEL ===\n\n' .. text, '\n', { plain = true }))
  -- Dit bestand test de importwaarschuwing, niet de vervolgdialoog/extern zoeken.
  vim.b[buf].rubric_recognition_done = true
  vim.b[buf].edition_recognition_done = true
  return buf
end
local buf = source(body)
local native_system = vim.system
local launches = 0
vim.system = function(command, options, callback)
  launches = launches + 1
  assert(command[3] == 'texttools.import_inspection', 'Onverwacht extra subprocess')
  return native_system(command, options, callback)
end
local payload
ai._column_recognition_runner(buf, body, function(candidates, embargo, warnings)
  payload = { candidates = candidates, embargo = embargo, warnings = warnings }
end)
assert(vim.wait(10000, function() return payload ~= nil end), 'Importinspectie bleef hangen')
assert(launches == 1, 'Waarschuwing veroorzaakte extra processen')
assert(payload.warnings[1].dateline_count == 2, 'Gedeelde waarschuwing ging verloren')

local runner = ai._column_recognition_runner
ai._column_recognition_runner = function(_, _, done)
  done(payload.candidates, payload.embargo, payload.warnings)
end
local other = source('Ander artikel zonder plaatskop.')
vim.api.nvim_set_current_buf(other)
local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
ai._article_autodetect(buf)
local entries = warnings(buf)
assert(#entries == 1 and entries[1].level == vim.log.levels.WARN,
  'Importwaarschuwing ontbreekt in het artikel-logboek: ' .. vim.inspect(entries))
assert(entries[1].message == payload.warnings[1].message, 'Client veranderde het kernadvies')
assert(#warnings(other) == 0, 'Waarschuwing belandde bij een ander artikel')
assert(vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
  'Waarschuwing wijzigde of splitste het artikel')
ai._article_autodetect(buf)
assert(#warnings(buf) == 1, 'Dezelfde import kreeg een dubbele waarschuwing')

-- Oudere kern zonder warnings blijft bruikbaar.
ai._column_recognition_runner = function(_, _, done) done({}, { detected = false }) end
ai._article_autodetect(other)
assert(#warnings(other) == 0, 'Oud contract leverde een nepwaarschuwing')

-- Een laat inspectieresultaat mag geen waarschuwing over oude tekst tonen.
local stale = source(body)
local deliver
ai._column_recognition_runner = function(_, _, done) deliver = done end
ai._article_autodetect(stale)
vim.api.nvim_buf_set_lines(stale, -1, -1, false, { 'Nieuwere tekst.' })
deliver({}, { detected = false }, payload.warnings)
for _, entry in ipairs(warnings(stale)) do
  assert(entry.message ~= payload.warnings[1].message, 'Verouderd advies werd toch getoond')
end

-- Een echte ruwe agendaverzameling start geen artikelinspectie.
local agenda = source('dinsdag 20 oktober\n10.00 uur | Kerk\nKAMPEN - Concert.\n\nwoensdag 21 oktober\n12.00 uur | Plein\nZWOLLE - Markt.')
ai._column_recognition_runner = function() error('Agenda startte losse-artikelinspectie') end
local agenda_module = require 'agenda_page'
local original_measure = agenda_module.measure
agenda_module.measure = function(target, options)
  assert(target == agenda and options.automatic, 'Agenda kreeg geen eigen omvangmeting')
end
ai._article_autodetect(agenda)
agenda_module.measure = original_measure
assert(#warnings(agenda) == 0, 'Agendaverzameling kreeg een importwaarschuwing')
assert(launches == 1, 'Logboekweergave veroorzaakte extra subprocessen')
ai._column_recognition_runner, vim.system = runner, native_system
print 'import warnings: OK'
