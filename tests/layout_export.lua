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

vim.fn.delete(tmp, 'rf')
print('layout export: OK')
