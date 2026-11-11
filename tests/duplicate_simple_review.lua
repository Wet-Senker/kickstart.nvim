local ui = require 'duplicate_selection_ui'
local function key(buf, name)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs:lower() == name:lower() then map.callback(); return end
  end
  error(name)
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local report = { candidates = {
  { kind = 'web', variants = {
    { headline = 'Treffer Brug', edition = 'B', review_selectable = true, review_target = { id = 'b' } },
    { headline = 'Treffer Zwolle', edition = 'SW', review_selectable = true, review_target = { id = 'sw' } },
    { headline = 'Alleen lezen', edition = 'D', review_selectable = false },
  } },
  { kind = 'agenda', variants = {
    { headline = 'Agenda-afspraak', edition = 'B', review_selectable = true, review_target = { id = 'agenda' } },
  } },
} }
local closed, applied
local options = { simple_review = true, on_apply = function(_, choices, done)
  applied = vim.deepcopy(choices); done(true)
end }
ui.show(vim.deepcopy(report), function(ok) closed = ok end, options)
local buf = vim.api.nvim_get_current_buf()
assert(not text(buf):find('Onbeoordeeld', 1, true) and not text(buf):find('Webdoublure:', 1, true))
assert(text(buf):find('Treffer Brug', 1, true) and text(buf):find('Agenda-afspraak', 1, true))
key(buf, 'n')
assert(closed and vim.deep_equal(applied, { b = 'different', sw = 'different', agenda = 'different' }))
closed, applied = nil, nil
local duplicate = vim.deepcopy(report)
ui.show(duplicate, function(ok) closed = ok end, options)
buf = vim.api.nvim_get_current_buf()
key(buf, 'm')
assert(closed == false and duplicate.article_duplicate and not applied)
-- De zichtbare knoppen voeren dezelfde twee acties uit als de toetsen.
local original_mouse = vim.fn.getmousepos
for _, choice in ipairs({ 'Geen doublure', 'Wel doublure' }) do
  closed, applied = nil, nil
  local clicked = vim.deepcopy(report)
  ui.show(clicked, function(ok) closed = ok end, options)
  buf = vim.api.nvim_get_current_buf()
  local row, column
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find('[Geen doublure', 1, true) then row, column = index, assert(line:find(choice, 1, true)); break end
  end
  vim.fn.getmousepos = function() return { winid = vim.api.nvim_get_current_win(), line = row, column = column } end
  key(buf, '<LeftMouse>')
  assert(closed == (choice == 'Geen doublure'))
  assert((applied ~= nil) == (choice == 'Geen doublure'))
end
vim.fn.getmousepos = original_mouse
closed, applied = nil, nil
closed = nil
ui.show({ errors = { 'Controle onvolledig' }, candidates = report.candidates },
  function(ok) closed = ok end, options)
buf = vim.api.nvim_get_current_buf()
key(buf, 'n')
assert(closed == nil and not applied and vim.api.nvim_buf_is_valid(buf))
key(buf, '<C-c>')
assert(closed == false)
print('simple duplicate review: OK')
