local browser = require 'ordered_browser'
local notifications = require 'texttools_notify'
local opened, calls = {}, {}
browser.open_urls = function(urls) opened[#opened + 1] = vim.deepcopy(urls) end
local pending_mark
local pair = {
  left = { title = 'Links', headline = 'Links', date = '2026-10-20', editor_url = 'left' },
  right = { title = 'Rechts', headline = 'Rechts', editor_url = 'right' },
  score = 90, reason = 'gelijke inhoud', review_key = string.rep('a', 64),
  group_id = 1,
}
local groups = {
  { id = 1, article_count = 4, open_urls = { 'left', 'right', 'third', 'fourth', 'right' } },
  { id = 2, article_count = 2, open_urls = { 'unrelated-a', 'unrelated-b' } },
}
local selected_urls = { 'left', 'right', 'third', 'fourth' }
notifications.system = function(cmd, opts, done)
  calls[#calls + 1] = cmd
  if vim.tbl_contains(cmd, 'eigen-doublures') then
    done { code = 0, stdout = vim.json.encode { edities = { { editie = 'B', paren = { vim.deepcopy(pair) }, groups = groups } } } }
  elseif vim.tbl_contains(cmd, 'doublure-geen') or vim.tbl_contains(cmd, '--mark-reviewed') then
    assert(vim.json.decode(opts.stdin).review_keys[1] == pair.review_key)
    pending_mark = done
  else
    done { code = 0, stdout = vim.json.encode { sites = { { publication = 'B', pairs = { vim.deepcopy(pair) }, groups = groups } } } }
  end
  return {}
end
local function key(buf, name)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs == name then mapping.callback(); return end
  end
  error('Ontbrekende toets: ' .. name)
end
local function row_containing(text)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(text, 1, true) then vim.api.nvim_win_set_cursor(0, { row, 0 }); return end
  end
  error('Ontbrekende regel: ' .. text)
end

local sites = require 'site_duplicates'
sites.run('all', { open_browser = true }) -- Legacy flag must NOT revive bulk opening.
assert(vim.wait(1000, function() return vim.api.nvim_buf_get_name(0):find('Webartikel-doublures', 1, true) end))
assert(#opened == 0, 'webscan opende automatisch tabbladen')
local buf = vim.api.nvim_get_current_buf()
row_containing('gelijke inhoud')
key(buf, 'o')
assert(vim.deep_equal(opened[1], selected_urls), 'o moet alle vier groepsartikelen eenmaal openen, niet de andere groep')
row_containing('Rechts')
key(buf, 'o')
assert(vim.deep_equal(opened[2], selected_urls), 'o op rechterartikel moet dezelfde hele groep openen')
key(buf, 'm')
assert(pending_mark, 'webbeoordeling moet naar Python')
key(buf, 'q')
pending_mark { code = 0, stdout = '{"schema_version":1,"marked_count":1}' }
vim.wait(20, function() return false end) -- Callback after close may not recreate/modify report.
assert(not vim.api.nvim_buf_is_valid(buf))

require('agenda_menu').eigen_doublures()
assert(vim.wait(1000, function() return vim.api.nvim_buf_get_name(0):find('Eigen doublures', 1, true) end))
assert(#opened == 2, 'agendascan opende automatisch tabbladen')
buf = vim.api.nvim_get_current_buf()
row_containing('Links')
key(buf, 'o')
assert(vim.deep_equal(opened[3], selected_urls), 'agendagroep werd afgekapt op twee artikelen')
key(buf, 'm')
pending_mark { code = 0, stdout = '{"schema_version":1,"marked_count":1}' }
assert(vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('✓ Geen doublure', 1, true)
end))
key(buf, 'q')

-- One selected Pubble candidate, not blanket approval. A failed save keeps it pending.
local duplicates = require 'pubble_duplicates'
local result = { candidates = {
  { headline = 'Een', key = 'one', variants = { { publication = 'B', headline = 'Een', editor_url = 'one' } } },
  { headline = 'Twee', key = 'two', variants = { { publication = 'B', headline = 'Twee', editor_url = 'two' } } },
} }
local decision, saved
duplicates.show(result, function(value) decision = value end, {
  on_mark = function(candidate, done) saved = { candidate = candidate, done = done } end,
})
buf = vim.api.nvim_get_current_buf()
row_containing('Een')
key(buf, 'm')
assert(saved.candidate.key == 'one' and decision == nil)
saved.done(false)
assert(not result.candidates[1].reviewed)
key(buf, 'm')
saved.done(true)
assert(result.candidates[1].reviewed and not result.candidates[2].reviewed and decision == nil)
row_containing('Twee')
key(buf, 'o')
assert(vim.deep_equal(opened[4], { 'two' }), 'invoercheck mag niet andere krantenversies openen')
key(buf, 'm')
saved.done(true)
assert(decision == true, 'alle afzonderlijk beoordeelde kandidaten moeten vervolg vrijgeven')

-- Text view retains the selected candidate for o/m, never a row from the report.
duplicates.show({ candidates = { { headline = 'Drie', variants = { {
  publication = 'B', headline = 'Drie', editor_url = 'three', text = 'Tekst',
} } } } }, function() end)
buf = vim.api.nvim_get_current_buf()
key(buf, '<CR>')
key(buf, 'o')
assert(vim.deep_equal(opened[5], { 'three' }))
key(buf, 'q')
key(buf, 'q')

-- Agenda input is asynchronous and browsing respects the selected existing item.
local ai = require 'ai_text'
local source = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'Artikel' })
local choice = 'pending'
ai._agenda_duplicate_confirm(source, { candidates = {
  { editie = 'B', bestaand_titel = 'Eerste', url = 'first' },
  { editie = 'SW', bestaand_titel = 'Tweede', url = 'second' },
} }, function(value) choice = value end)
assert(choice == 'pending', 'agenda-beoordeling mag niet synchronisch blokkeren')
buf = vim.api.nvim_get_current_buf()
row_containing('Tweede')
key(buf, 'o')
assert(vim.deep_equal(opened[6], { 'second' }))
key(buf, 'n')
assert(choice == false, 'n betekent expliciet geen nieuw agenda-item')

print('duplicate pair navigation: OK')
