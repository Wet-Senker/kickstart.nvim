local folds = require('article_metadata_fold')
vim.system = function() error('metadataweergave mag geen subprocess starten') end
folds.setup()
local function drain()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  assert(vim.wait(1000, function() return done end, 5))
end
local function source(lines, filetype)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.wo.foldmethod = 'manual'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or 'markdown'
  drain()
  return buf
end
local metadata = { '---', 'calendar:', '  event_candidate: true', '  event_date: 2099-10-31',
  'calendar_preparation:', '  version: 1', '  state: prepared', '---' }
local article = { '', 'e: SW, BR', 'wijk: Holtenbroek', 'Foto: Test', '', '=== ARTIKEL ===', '',
  'Concert in Hedon', '', 'ZWOLLE - Een concert.', '', '---', '', '## Kalender', '',
  'Titel: Concert', 'Datum: 2099-10-31', 'Stad: Zwolle' }
local lines = vim.list_extend(vim.deepcopy(metadata), article)
local buf = source(lines)
assert(vim.fn.foldclosed(1) == 1 and vim.fn.foldclosedend(1) == #metadata, 'alleen YAML moet dicht')
assert(vim.fn.foldtextresult(1) == 'Technische gegevens · zo openen / zc sluiten')
for at = #metadata + 1, #lines do
  assert(vim.fn.foldlevel(at) == 0, 'instellingen, artikel of kalender werden verborgen')
end

-- Openen/sluiten zijn gewone Vim-acties; geen tekst-, undo- of opslagwijziging.
vim.bo[buf].modified = false
local tick, undo = vim.api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur
vim.cmd('normal! zo')
assert(vim.fn.foldclosed(1) == -1, 'zo opent de metadata niet')
vim.cmd('normal! zc')
assert(vim.fn.foldclosedend(1) == #metadata)
folds.attach(buf); drain()
assert(vim.api.nvim_buf_get_changedtick(buf) == tick and vim.fn.undotree().seq_cur == undo)
assert(not vim.bo[buf].modified and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines))
local saved = vim.fn.tempname() .. '.md'
vim.api.nvim_buf_call(buf, function() vim.cmd('silent write ' .. vim.fn.fnameescape(saved)) end)
assert(vim.deep_equal(vim.fn.readfile(saved), lines), 'opslaan verloor technische gegevens')

-- Een gewone bodybewerking mag een bewust geopende vouw niet dichtdrukken.
vim.cmd('normal! zo')
vim.api.nvim_buf_set_lines(buf, #metadata + 9, #metadata + 10, false, { 'ZWOLLE - Nieuw concert.' })
drain()
assert(vim.fn.foldclosed(1) == -1, 'bodybewerking sloot debugweergave')
-- Ook metadata bewerken met gelijkblijvende of veranderde omvang blijft open.
vim.api.nvim_buf_set_lines(buf, 3, 4, false, { '  event_date: 2099-11-01' })
drain()
assert(vim.fn.foldclosed(1) == -1)
vim.api.nvim_buf_set_lines(buf, 4, 4, false, { '  city: Zwolle' })
drain()
assert(vim.fn.foldclosed(1) == -1, 'metadata aanvullen drukte de vouw dicht')
vim.cmd('1foldclose')
assert(vim.fn.foldclosedend(1) == #metadata + 1)

-- Later ingevoegde metadata, ook via vervanging van de gehele buffer.
buf = source(article)
assert(vim.fn.foldlevel(1) == 0)
vim.api.nvim_win_set_cursor(0, { 10, 2 })
vim.api.nvim_buf_set_lines(buf, 0, 0, false, metadata)
local cursor = vim.api.nvim_win_get_cursor(0)
drain()
assert(vim.fn.foldclosedend(1) == #metadata)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor), 'automatisch vouwen verplaatste de tekstcursor')
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
drain()
assert(vim.fn.foldclosedend(1) == #metadata, 'volledige bufferupdate vouwde de artikelbody mee')

-- Meerdere vensters krijgen elk een gesloten beginweergave. Later openen in
-- het ene venster hoeft de andere weergave niet te openen.
vim.cmd('vsplit')
local split = vim.api.nvim_get_current_win()
drain()
assert(vim.fn.foldclosedend(1) == #metadata)
assert(vim.fn.foldtextresult(1) == 'Technische gegevens · zo openen / zc sluiten', 'split verloor het label')
vim.cmd('1foldopen')
vim.cmd('wincmd p')
assert(vim.fn.foldclosed(1) == 1, 'openen werkte onbedoeld in een ander venster')
vim.api.nvim_win_close(split, true)

-- Andere handmatige vouwen behouden hun eigen bereik en foldtext.
buf = source(article)
vim.wo.foldtext = "'Eigen vouw'"
vim.cmd('8,10fold')
vim.api.nvim_buf_set_lines(buf, 0, 0, false, metadata)
drain()
assert(vim.fn.foldclosedend(1) == #metadata)
assert(vim.fn.foldclosed(#metadata + 8) == #metadata + 8)
assert(vim.fn.foldclosedend(#metadata + 8) == #metadata + 10)
assert(vim.fn.foldtextresult(#metadata + 8) == 'Eigen vouw')
-- Voorblok verwijderen ruimt alleen onze eigen vouw op.
vim.api.nvim_buf_set_lines(buf, 0, #metadata, false, {})
drain()
assert(vim.fn.foldlevel(1) == 0 and vim.fn.foldclosed(8) == 8)
assert(vim.wo.foldtext == "'Eigen vouw'")

-- Terugkeren naar een buffer hergebruikt de bestaande metadataweergave.
local with_metadata = source(lines)
source(article)
vim.api.nvim_set_current_buf(with_metadata)
drain()
assert(vim.fn.foldclosedend(1) == #metadata)
assert(vim.fn.foldtextresult(1) == 'Technische gegevens · zo openen / zc sluiten')

source(vim.list_extend(vim.deepcopy(metadata), { '', 'e: SW', '', '=== AGENDAPAGINA ===', '', 'Uitjes' }))
assert(vim.fn.foldclosedend(1) == #metadata)

-- Gewone Markdown, onvolledige YAML en niet-artikelbuffers blijven ongemoeid.
for _, example in ipairs({
  { '---', 'Een gewone scheidingslijn', '---', 'Tekst' },
  { '---', 'calendar:', '=== ARTIKEL ===', 'Kop' },
  { '---', 'title: Document', '---', '# Geen Texttools-artikel' },
  { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', '---', '', '## Kalender' },
}) do
  source(example)
  assert(vim.fn.foldlevel(1) == 0, 'gewone tekst werd als technische metadata verborgen')
end
source(lines, 'lua')
assert(vim.fn.foldlevel(1) == 0, 'codebuffer kreeg een artikelvouw')
-- Een bewust ingestelde andere methode wordt niet overschreven.
buf = source(article)
vim.wo.foldmethod = 'marker'
vim.api.nvim_buf_set_lines(buf, 0, 0, false, metadata)
drain()
assert(vim.wo.foldmethod == 'marker')

-- Dezelfde bron zonder bestandsnaam of alleen-lezen moet ook leesbaar blijven.
buf = source(lines, 'text')
vim.bo[buf].readonly = true
vim.bo[buf].modifiable = false
folds.attach(buf); drain()
assert(vim.fn.foldclosedend(1) == #metadata)
-- Een gesloten buffer mag een reeds geplande update niet laten crashen.
buf = source(article)
vim.api.nvim_buf_set_lines(buf, 0, 0, false, metadata)
vim.api.nvim_buf_delete(buf, { force = true })
drain()
print('article metadata fold: OK')
