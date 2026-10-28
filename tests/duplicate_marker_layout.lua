local folds = require('article_metadata_fold')
local layout = require('duplicate_marker_layout')
local native_system, calls = vim.system, 0
vim.system = function(command, options, callback)
  if vim.tbl_contains(command, 'texttools.duplicate_selection') then calls = calls + 1 end
  return native_system(command, options, callback)
end
folds.setup()
local function wait(test) assert(vim.wait(5000, test, 5), 'markerindeling bleef wachten') end
local function content(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local legacy = { '---', 'duplicate_selection: {version: 1, entries: []}', '---', '',
  'c: Jan Jansen', 'doublures: beoordeeld', 'e: B', '', '[09:18] Import opgeschoond.', '',
  '=== ARTIKEL ===', '', '**Een kop**', '', 'De artikeltekst.', '', '## Facebook', '', 'Socialtekst.' }
local function source(readonly)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, legacy)
  if readonly then vim.bo[buf].readonly, vim.bo[buf].modifiable = true, false end
  vim.bo[buf].filetype = 'markdown'
  return buf
end
local buf = source()
wait(function() return vim.fn.foldclosedend(1) == 4 end)
assert(calls == 1 and vim.fn.foldtextresult(1) == 'Gegevens verborgen · :ArtikelMetadata')
assert(vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'doublures: beoordeeld')
local text = content(buf)
assert(text:find('c: Jan Jansen\ne: B', 1, true), 'zichtbare instellingen raakten vermengd')
assert(text:match('=== ARTIKEL ===.*') == table.concat(legacy, '\n'):match('=== ARTIKEL ===.*'))
for _ = 1, 3 do folds.attach(buf); folds.refresh(buf) end
assert(calls == 1, 'elke schermverversing startte een nieuw proces')
require('ai_text')._set_edition_codes(buf, { 'B', 'SW' })
wait(function() return vim.fn.foldclosedend(1) == 4 end)
assert(vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1] == 'doublures: beoordeeld')
assert(calls == 1, 'editiewijziging maakte weer een zichtbare guard of een proces')
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwe eigen regel.' })
assert(content(buf):find('Nieuwe eigen regel.', 1, true))

-- Read-only documenten nooit ongemerkt migreren.
buf = source(true)
vim.wait(50, function() return false end)
assert(calls == 1 and content(buf) == table.concat(legacy, '\n'))

-- Een laat formatterresultaat mag zelfs een nieuwe meldregel niet overschrijven.
buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, legacy)
local done
layout.normalize(buf, function(ok) done = ok end)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwste eigen tekst tijdens de migratie.' })
wait(function() return done ~= nil end)
assert(done and content(buf):find('Nieuwste eigen tekst tijdens de migratie.', 1, true))
assert(calls == 3, 'wijzigingsrace moet één begrensde lokale herhaling gebruiken')
print('duplicate marker layout: OK')
