local dialog = require 'user_dialog'
local krant = require 'krant'
local calls, selected = 0, nil
local native = vim.ui.select
local question
-- Use the real dialog queue and an injected search presentation.
dialog.setup { search_select = function(items, opts, done)
  calls = calls + 1
  assert(opts.searchable and opts.format_item)
  local matches = {}
  for _, item in ipairs(items) do
    if opts.format_item(item):lower():find('honden', 1, true) then matches[#matches + 1] = item end
  end
  assert(#matches == 1 and matches[1].name == 'Hondenhoek')
  done(matches[1])
end }
krant.stock_rubriek_flow = function(config)
  selected = config
end
krant.menu()
assert(vim.wait(1000, function() return selected ~= nil end, 5))
assert(selected.edition == 'B' and calls == 1)
for _, template in ipairs(krant.templates) do
  assert(template.edition == 'B', 'rubriek mist De Brug: ' .. template.name)
end
-- Other selection lists retain their native numbered display.
dialog.select({ 'Ja', 'Nee' }, { prompt = 'Controle', default = 2 }, function(item) question = item end)
assert(vim.wait(1000, function()
  return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == 'editor'
end, 5))
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(question == 'Nee' and calls == 1)
vim.ui.select = native
print('rubric search menu: OK')

-- Intake creates an empty e: placeholder. It is not an explicit destination.
for _, key in ipairs({ 'e:', 'editie:   ' }) do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { key, 'agenda: nee', '', '=== ARTIKEL ===', '', 'Hondenhoek', '', 'Eigen tekst.' })
  assert(krant.ensure_detected_rubric_edition('hondenhoek', buf), 'lege editie werd niet hersteld')
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(text:find('e: B', 1, true) and text:find('Eigen tekst.', 1, true))
  assert(not krant.ensure_detected_rubric_edition('hondenhoek', buf), 'herstel is niet idempotent')
end
local buf = vim.api.nvim_create_buf(false, true)
local lines = { 'e: SW', '', '=== ARTIKEL ===', '', 'Hondenhoek', '', 'Eigen tekst.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
assert(not krant.ensure_detected_rubric_edition('hondenhoek', buf), 'bewuste editie overschreven')
assert(vim.deep_equal(lines, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
