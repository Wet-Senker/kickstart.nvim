local ai = require 'ai_text'
local buf = vim.api.nvim_create_buf(false, true)
local function command(dates, editions)
  vim.b[buf].publication_review_state = { display_dates = dates }
  local result = { 'aitext', 'journalistiek_schrijven' }
  ai._append_reference_date(result, buf, editions)
  return result
end
assert(vim.deep_equal(command { B = '2026-10-28' },
  { 'aitext', 'journalistiek_schrijven', '--reference-date', '2026-10-28' }))
for _, value in ipairs { '2026-10-28:2', '2026-10-28:krant' } do
  assert(vim.deep_equal(command { B = value },
    { 'aitext', 'journalistiek_schrijven', '--reference-date', '2026-10-28' }))
end
assert(vim.deep_equal(command { B = '2026-10-28:2', SW = '2026-10-28:krant' },
  { 'aitext', 'journalistiek_schrijven', '--reference-date', '2026-10-28' }))
assert(vim.deep_equal(command({ B = '2026-10-28', SW = '2026-10-29' }, { 'SW' }),
  { 'aitext', 'journalistiek_schrijven', '--reference-date', '2026-10-29' }))
assert(#command { B = 'direct' } == 2)
assert(#command { B = '2026-10-28', SW = 'direct' } == 2)
assert(#command { B = '2026-10-28', SW = '2026-10-29' } == 2)
assert(#command({ B = '2026-10-28' }, { 'B', 'SW' }) == 2)
assert(#command {} == 2)
assert(vim.deep_equal(command { B = '2026-10-25T23:30:00Z' },
  { 'aitext', 'journalistiek_schrijven', '--reference-date', '2026-10-25T23:30:00Z' }))
local dialog = require 'user_dialog'
local original = dialog.confirm
local captured
dialog.confirm = function(prompt) captured = prompt; return 1 end
ai._newspaper_time_version_choice({ { edition = 'B', newspaper_date = '2026-10-27',
  transitions = { { start = '2026-09-26', ['end'] = vim.NIL, newspaper_state = 'unknown_end' } } } })
assert(captured:find('begonnen; einde onbekend', 1, true))
assert(not captured:find('vim.NIL', 1, true) and not captured:find('afgelopen', 1, true))
dialog.confirm = original
print 'writing date context: OK'
