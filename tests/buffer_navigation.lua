local nav = require 'buffer_navigation'
nav.setup()
vim.o.hidden = false
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'Artikel', 'Onopgeslagen tekst', 'Derde regel' })
vim.bo[source].bufhidden = 'wipe'
vim.api.nvim_win_set_cursor(0, { 2, 5 })
vim.wo.wrap, vim.wo.number, vim.wo.foldmethod = false, true, 'indent'
local lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
local tick, undo = vim.api.nvim_buf_get_changedtick(source), vim.fn.undotree().seq_cur
local function view()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Overzicht', 'Tweede regel' })
  vim.bo[buf].bufhidden, vim.bo[buf].modifiable = 'wipe', false
  nav.show(buf)
  return buf
end
local overview = view()
vim.wo.wrap, vim.wo.number, vim.wo.foldmethod = true, false, 'manual'
vim.api.nvim_win_set_cursor(0, { 2, 2 })
local detail = view()
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'hulpschermen maakten splits')
vim.fn.maparg('q', 'n', false, true).callback()
assert(vim.api.nvim_get_current_buf() == overview and not vim.api.nvim_buf_is_valid(detail))
assert(vim.api.nvim_win_get_cursor(0)[1] == 2 and vim.wo.wrap and not vim.wo.number, 'geneste terugweg verloor schermpositie')
vim.cmd 'TexttoolsTerug'
assert(vim.api.nvim_get_current_buf() == source and not vim.api.nvim_buf_is_valid(overview))
assert(not vim.wo.wrap and vim.wo.number and vim.wo.foldmethod == 'indent', 'bronvensteropties verloren')
assert(vim.api.nvim_win_get_cursor(0)[2] == 5 and vim.bo[source].modified and vim.bo[source].bufhidden == 'wipe')
assert(vim.api.nvim_buf_get_changedtick(source) == tick and vim.fn.undotree().seq_cur == undo)
assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(source, 0, -1, false)), 'broninhoud gewijzigd')

-- Bewerkbare uitvoer blijft in de bufferlijst; q blijft beschikbaar voor
-- Neovim-macro's. Terugkeren is geen weggooien of opslaan van het document.
local generated = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(generated, 0, -1, false, { 'Nieuwe tekst' })
nav.show(generated, { editable = true })
assert(vim.fn.maparg('q', 'n') == '' and vim.bo[generated].buflisted)
vim.cmd 'TexttoolsTerug'
assert(vim.api.nvim_buf_is_valid(generated) and vim.api.nvim_buf_get_lines(generated, 0, -1, false)[1] == 'Nieuwe tekst')
assert(vim.bo[generated].bufhidden == 'hide' and vim.api.nvim_get_current_buf() == source)

-- Een door de gebruiker gemaakte split blijft precies zo groot en intact.
vim.cmd 'vsplit'
local win = vim.api.nvim_get_current_win()
local width = vim.api.nvim_win_get_width(win)
local height = vim.api.nvim_win_get_height(win)
local scratch = view()
nav.back(scratch)
assert(#vim.api.nvim_tabpage_list_wins(0) == 2)
assert(vim.api.nvim_win_get_width(win) == width and vim.api.nvim_win_get_height(win) == height)

-- Handmatig gewisseld: een late sluitcallback springt niet terug naar de
-- bron en mag het nieuwe document nooit wissen.
scratch = view()
vim.api.nvim_win_set_buf(win, generated)
assert(not nav.back(scratch) and vim.api.nvim_get_current_buf() == generated)
local next_view = view()
nav.back(next_view)
assert(vim.api.nvim_get_current_buf() == generated and not nav.back())

-- Een verdwenen bron levert een leeg bewerkbaar scherm, geen fout/loop.
scratch = view()
vim.api.nvim_buf_delete(generated, { force = true })
assert(nav.back(scratch) and vim.bo.modifiable)
assert(vim.api.nvim_buf_is_valid(source), 'andere bron gewist')
print 'buffer navigation: OK'
