local ui = require 'duplicate_selection_ui'
local function key(buf, name)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == name then map.callback(); return end
  end
  error('toets ontbreekt: ' .. name)
end
local applied, closed
ui.show({ candidates = {}, saved_selections = {}, errors = {}, agenda_only_offers = {
  { id = 'agenda-only:1', edition = 'SW', item_key = 'event-1', title = 'Concert', selected = false },
} }, function(ok) closed = ok end, { on_apply = function(_, choices, done)
  assert(choices['agenda-only:1'] == 'different')
  applied = true
  done(true)
end })
local buf = vim.api.nvim_get_current_buf()
local function text() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
assert(text():find('Alleen agenda: Concert', 1, true))
key(buf, 'a')
assert(text():find('[+] Alleen agenda:', 1, true))
assert(not applied and not closed, 'selecteren mag niets opslaan of publiceren')
key(buf, 'a')
assert(text():find('[ ] Alleen agenda:', 1, true))
key(buf, 'a'); key(buf, 'q')
assert(applied and closed)
