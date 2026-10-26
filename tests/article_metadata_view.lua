local metadata = require 'article_metadata_fold'
metadata.setup()
vim.system = function() error('metadata bekijken mag geen subprocess starten') end
local function drain()
  vim.wait(25, function() return false end)
end
local technical = { '---', 'media:', '  credit: Jan Jansen', 'web:', '  article_id: 123', '---' }
local content = { '', 'e: B', 'c: Jan Jansen', '', '=== ARTIKEL ===', '', '**Een kop**', '', 'De artikeltekst.' }
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(vim.deepcopy(technical), content))
vim.bo[buf].filetype = 'markdown'
drain()
vim.api.nvim_win_set_cursor(0, { #technical + 7, 2 })
vim.bo[buf].modified = false
local editor, cursor = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0)
local tick, undo = vim.api.nvim_buf_get_changedtick(buf), vim.fn.undotree().seq_cur
local view, win = metadata.show()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(view, 0, -1, false), technical))
assert(vim.bo[view].readonly and not vim.bo[view].modifiable and vim.bo[view].buftype == 'nofile')
assert(vim.wo[win].winblend == 0)
assert(vim.b[view].texttools_activity_source == buf)
assert(vim.api.nvim_buf_get_changedtick(buf) == tick and not vim.bo[buf].modified)
assert(vim.api.nvim_buf_call(buf, function() return vim.fn.undotree().seq_cur end) == undo)
vim.fn.maparg('q', 'n', false, true).callback()
assert(not vim.api.nvim_win_is_valid(win) and not vim.api.nvim_buf_is_valid(view))
assert(vim.api.nvim_get_current_win() == editor and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor))

-- Een verzendbevestiging blijft leesbaar; alleen YAML gaat naar de kijkweergave.
local receipt = { '**Verstuurd naar Pubble op 26-10-2026 10:00**', 'https://brugmedia.pubble.nl/articles/123', '' }
vim.api.nvim_buf_set_lines(buf, 0, 0, false, receipt)
drain()
for row = 1, #receipt do assert(vim.fn.foldlevel(row) == 0, 'verzendbevestiging werd verborgen') end
assert(vim.fn.foldclosed(#receipt + 1) == #receipt + 1, 'YAML na verzending bleef zichtbaar')
assert(vim.fn.foldclosedend(#receipt + 1) == #receipt + #technical)
assert(vim.fn.foldtextresult(#receipt + 1) == 'Gegevens verborgen · :ArtikelMetadata')
vim.cmd 'ArtikelMetadata'
view, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(view, 0, -1, false), technical))
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == receipt[1])
vim.fn.maparg('<Esc>', 'n', false, true).callback()
assert(vim.api.nvim_get_current_buf() == buf)

-- Native zR mag gegevens niet permanent zichtbaar maken; de body blijft gelijk.
vim.cmd 'normal! zR'
local before_close = vim.api.nvim_win_get_cursor(0)
vim.api.nvim_exec_autocmds('SafeState', {})
assert(vim.fn.foldclosed(#receipt + 1) == #receipt + 1)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), before_close), 'sluiten verplaatste de tekstcursor')
vim.wo.foldenable = false
vim.api.nvim_exec_autocmds('SafeState', {})
assert(vim.fn.foldclosed(#receipt + 1) == #receipt + 1, 'zi liet technische gegevens open')

-- Ook een kleine editor krijgt een begrensd venster, zonder bestandsschrijfroute.
vim.o.columns, vim.o.lines = 42, 14
view, win = metadata.show()
assert(vim.api.nvim_win_get_width(win) <= 36 and vim.api.nvim_win_get_height(win) <= 6)
vim.api.nvim_win_close(win, true)
local unchanged = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
vim.bo[buf].readonly, vim.bo[buf].modifiable = true, false
view, win = metadata.show()
assert(view and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), unchanged))
vim.api.nvim_win_close(win, true)
print 'article metadata view: OK'
