local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')
package.path = repo_root .. '/lua/?.lua;' .. package.path

local prose = require 'prose_editor'
assert(prose.spelllang == 'nl,en_us', 'proza moet Nederlandse en Engelse spelling configureren')
-- De minimale test-runtime bevat geen Nederlandse woordenlijst. Gebruik voor
-- het toepassen de ingebouwde Engelse lijst; de productiestandaard is hierboven
-- afzonderlijk gecontroleerd.
prose.spelllang = 'en_us'
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo[buf].filetype = 'markdown'
prose.apply(buf, vim.api.nvim_get_current_win())

assert(vim.wo.wrap, 'proza moet zacht omlopen')
assert(vim.wo.linebreak, 'proza moet bij woordgrenzen omlopen')
assert(vim.wo.breakindent, 'visuele vervolgregels moeten hun context behouden')
assert(vim.wo.breakindentopt == 'min:40,list:-1', 'lijsten moeten natuurlijk uitlijnen')
assert(vim.wo.showbreak == '', 'een visueel afbreekteken maakt proza onrustig')
assert(vim.wo.smoothscroll, 'lange visuele regels moeten vloeiend scrollen')
assert(not vim.wo.list, 'witruimtemarkeringen horen niet in de prozaweergave')
assert(vim.wo.colorcolumn == '', 'proza heeft geen harde kolomgrens')
assert(vim.wo.spell, 'spellingscontrole moet actief zijn voor proza')
assert(vim.wo.conceallevel == 0, 'Markdown-markup moet tijdens gewoon bewerken stabiel zichtbaar blijven')
assert(vim.bo[buf].spelllang == 'en_us', 'de ingestelde spellingslijst moet worden toegepast')
assert(vim.bo[buf].textwidth == 0, 'zachte omlopen mogen geen regeleinden invoegen')
assert(vim.bo[buf].wrapmargin == 0, 'zachte omlopen mogen geen wrapmarge schrijven')

local j_map = vim.fn.maparg('j', 'n', false, true)
local k_map = vim.fn.maparg('k', 'n', false, true)
assert(j_map.buffer == 1 and j_map.expr == 1, 'j moet per schermregel bewegen')
assert(k_map.buffer == 1 and k_map.expr == 1, 'k moet per schermregel bewegen')

print('prose editor: OK')
