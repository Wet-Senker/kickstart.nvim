-- Archiefzoeker (<leader>aa) en de achtergrondtekst (<leader>as).
local archive = require 'archive_context'

local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')
local source = table.concat(vim.fn.readfile(repo_root .. '/lua/archive_context.lua'), '\n')

-- Een functie zonder mapping is onbereikbaar voor de redacteur (principe 12).
assert(
  source:find("vim.keymap.set('n', '<leader>aa'", 1, true),
  'geen registratie van <leader>aa'
)
assert(
  source:find("vim.keymap.set('n', '<leader>as'", 1, true),
  'geen registratie van <leader>as'
)
assert(type(archive.search) == 'function', 'search ontbreekt')
assert(type(archive.summarise) == 'function', 'summarise ontbreekt')
assert(type(archive.apply) == 'function', 'apply ontbreekt')

-- Het keuzeblok telt alleen genummerde regels, geen jaarkoppen of uitleg.
local document = table.concat({
  '<!-- archive-context-review: 1 -->',
  '<!-- selection-start -->',
  '## 2025',
  '1. Eerste kop — 18 september 2025 — De Brug — 400 woorden',
  '## 2024',
  '2. Tweede kop — 22 september 2024 — De Brug — 350 woorden',
  '<!-- selection-end -->',
}, '\n')
assert(archive._selection_count(document) == 2, 'keuzeregels verkeerd geteld')
assert(archive._selection_count('zonder keuzeblok') == 0, 'lege lijst telt niet als nul')

-- Bladeren hangt aan de artikeltekst: verandert die, dan begin je weer vooraan.
-- Zelfde regel als bij de doublurecontrole; na een herschrijving zijn de
-- ankerwoorden anders en klopt een oude positie niet meer.
local article = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(article, 0, -1, false, { 'Kop', '', 'KAMPEN - Tekst.' })
assert(archive._offset_for(article) == 0, 'een verse buffer begint niet op nul')

vim.b[article].archive_context_body = table.concat(
  vim.api.nvim_buf_get_lines(article, 0, -1, false), '\n'
)
vim.b[article].archive_context_offset = 5
assert(archive._offset_for(article) == 5, 'de bewaarde positie wordt genegeerd')

vim.api.nvim_buf_set_lines(article, -1, -1, false, { 'Een herschreven zin.' })
assert(archive._offset_for(article) == 0, 'de positie overleeft een tekstwijziging')

-- De achtergrond komt als zichtbare sectie onderaan, en vervangt een vorige.
local target = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(target, 0, -1, false, { '=== ARTIKEL ===', '', 'Mijn artikel.' })
archive.apply(target, 'Eerste achtergrond.')
local lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
local text = table.concat(lines, '\n')
assert(text:find('## Achtergrond', 1, true), 'de sectie is niet toegevoegd')
assert(text:find('Eerste achtergrond.', 1, true), 'de tekst ontbreekt')
assert(text:find('Mijn artikel.', 1, true), 'het artikel is beschadigd')

archive.apply(target, 'Tweede achtergrond.')
text = table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n')
local _, headings = text:gsub('## Achtergrond', '')
assert(headings == 1, 'er staan nu ' .. headings .. ' achtergrondsecties')
assert(not text:find('Eerste achtergrond.', 1, true), 'de oude achtergrond is blijven staan')
assert(text:find('Tweede achtergrond.', 1, true), 'de nieuwe achtergrond ontbreekt')
assert(text:find('Mijn artikel.', 1, true), 'het artikel is bij vervanging beschadigd')

-- Samenvatten kan alleen vanuit een archieflijst, en niet zonder keuze.
local warned = {}
local original_notify = vim.notify
vim.notify = function(message, level) table.insert(warned, message) end

archive.summarise(target)
assert(#warned == 1 and warned[1]:find('<leader>aa', 1, true),
  'samenvatten vanuit een gewone buffer geeft geen bruikbare melding')

local review = vim.api.nvim_create_buf(false, true)
vim.b[review].archive_context_review = true
vim.b[review].archive_context_source = target
vim.api.nvim_buf_set_lines(review, 0, -1, false, {
  '<!-- selection-start -->', '<!-- selection-end -->',
})
archive.summarise(review)
assert(#warned == 2 and warned[2]:find('minimaal één regel', 1, true),
  'een lege keuze wordt niet tegengehouden')

vim.notify = original_notify

print 'archive context: OK'
