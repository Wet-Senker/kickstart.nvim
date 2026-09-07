local layout_export = require('layout_export')

local tmp = vim.fn.tempname()
local layout_dir = tmp .. '/vormgeving'
local photo_src = tmp .. '/bron.jpg'
vim.fn.mkdir(tmp, 'p')
vim.fn.writefile({ 'foto' }, photo_src)

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '---',
  'media:',
  '  caption: "Een actueel bijschrift"',
  '  credit: "Foto: Testfotograaf"',
  '---',
  '',
  'prio: 1',
  '',
  '=== ARTIKEL ===',
  '',
  'Rubriekkop {{naam}}',
  '',
  'Oude tekst.',
  '',
  '> Een goede streamer',
})

local plan, prepare_error = layout_export.prepare(buf, {
  dir = layout_dir,
  txt_name = '1.rubriekFOTO.txt',
  img_name = '1.rubriekFOTO.jpg',
  photo_src = photo_src,
  label = 'Testrubriek',
})
assert(plan and not prepare_error, prepare_error or 'exportplan ontbreekt')
assert(vim.fn.filereadable(layout_dir .. '/1.rubriekFOTO.jpg') == 1, 'vormgevingsfoto is niet voorbereid')
assert(vim.fn.filereadable(layout_dir .. '/1.rubriekFOTO.txt') == 0, 'tekst is te vroeg geschreven')

local valid, validation_error = layout_export.validate(buf)
assert(not valid and validation_error:find('{{naam}}', 1, true), 'onopgeloste placeholder is niet geweigerd')

vim.api.nvim_buf_set_lines(buf, 10, 13, false, {
  'Rubriekkop ingevuld',
  '',
  'Actuele tekst na de templatekeuze.',
})

valid, validation_error = layout_export.validate(buf)
assert(valid and validation_error == nil, validation_error or 'ingevuld template bleef ongeldig')
local path, finalize_error = layout_export.finalize(buf)
assert(path == layout_dir .. '/1.rubriekFOTO.txt', finalize_error or 'onverwacht exportpad')
assert(layout_export.pending(buf) == nil, 'exportplan is na succes niet gewist')

local exported = table.concat(vim.fn.readfile(path), '\n')
assert(exported:find('Streamer: Een goede streamer', 1, true), 'streamer ontbreekt in vormgevingsexport')
assert(exported:find('Bijschrift: Een actueel bijschrift', 1, true), 'bijschrift ontbreekt in vormgevingsexport')
assert(exported:find('Fotograaf: Testfotograaf', 1, true), 'fotocredit ontbreekt in vormgevingsexport')
assert(exported:find('Actuele tekst na de templatekeuze.', 1, true), 'latere tekstwijziging ontbreekt')
assert(not exported:find('=== ARTIKEL ===', 1, true), 'artikelgrens lekte naar vormgeving')
assert(not exported:find('prio: 1', 1, true), 'controlecode lekte naar vormgeving')

-- Definitieve export haalt de werkelijk geüploade foto uit de Python-state.
local actual = tmp .. '/actual.jpg'
vim.fn.writefile({ 'actual uploaded bytes' }, actual, 'b')
local state = tmp .. '/published.md'
vim.fn.writefile({
  '---', 'media:', '  uploads:',
  '    ' .. vim.fn.sha256('actual uploaded bytes') .. ':',
  '      filename: actual.jpg', '      image_metadata_id: 42',
  '      stored_path: ' .. vim.json.encode(actual),
  '  caption: "Gedeeld bijschrift"',
  '---', '=== ARTIKEL ===', '',
  'FOTOBIJSCHRIFT: Gedeeld bijschrift', '',
  'Gepubliceerde [tekst](https://example.nl).', '',
  '---', '', '## Facebook', '', 'Niet voor vormgeving.',
}, state)
assert(layout_export.prepare(buf, { dir = layout_dir, txt_name = 'nature.txt' }))
local completed, error_result
layout_export.finalize_with_media(buf, state, function(result, err)
  completed = result or false
  error_result = err
end)
assert(vim.wait(5000, function() return completed ~= nil end, 10), 'foto-export bleef hangen')
assert(completed == layout_dir .. '/nature.txt', error_result or 'tekstexport ontbreekt')
assert(table.concat(vim.fn.readfile(layout_dir .. '/nature.jpg', 'b'), '\n') == 'actual uploaded bytes', 'definitieve uploadfoto ontbreekt')
local nature_text = table.concat(vim.fn.readfile(layout_dir .. '/nature.txt'), '\n')
assert(nature_text:find('Bijschrift: Gedeeld bijschrift', 1, true), 'bijschrift ontbreekt')
assert(not nature_text:find('FOTOBIJSCHRIFT', 1, true), 'dubbel zichtbaar bijschrift bleef staan')
assert(nature_text:find('Gepubliceerde tekst.', 1, true), 'Markdownlink werd niet platte tekst')
assert(not nature_text:find('Facebook', 1, true), 'Facebooksectie lekte naar vormgeving')

-- Een foto die na upload verdwijnt blokkeert afronding en behoudt het plan.
vim.fn.delete(actual)
assert(layout_export.prepare(buf, { dir = layout_dir, txt_name = 'retry.txt' }))
completed, error_result = nil, nil
layout_export.finalize_with_media(buf, state, function(result, err)
  completed = result or false
  error_result = err
end)
assert(vim.wait(5000, function() return completed ~= nil end, 10), 'exportfout bleef hangen')
assert(completed == false and error_result, 'ontbrekende foto werd genegeerd')
assert(layout_export.pending(buf), 'exportplan ging bij fout verloren')
assert(vim.fn.filereadable(layout_dir .. '/retry.txt') == 0, 'tekst werd ondanks ontbrekende foto afgerond')

vim.fn.delete(tmp, 'rf')
print('layout export: OK')
