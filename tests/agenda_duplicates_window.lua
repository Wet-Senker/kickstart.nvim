local notifications = require 'texttools_notify'
local agenda = require 'agenda_menu'
local pending, pending_mark, commands = nil, nil, {}
notifications.system = function(command, opts, callback)
  commands[#commands + 1] = command
  if vim.tbl_contains(command, 'eigen-doublures') then pending = callback
  elseif vim.tbl_contains(command, 'doublure-geen') then pending_mark = callback
  else error('Onverwachte opdracht: ' .. table.concat(command, ' ')) end
  return {}
end
local pair = {
  left = { title = 'Concert van een fanfare', date = '2099-12-01', editor_url = 'left' },
  right = { title = 'Concert met beroemde fanfare', editor_url = 'right' },
  review_key = string.rep('a', 64), score = 90, reason = 'Gelijke datum', group_id = 1,
}
local report = { van = '2099-12-01', tot = '2099-12-31', edities = {
  { editie = 'B', paren = { pair }, groups = { { id = 1, article_count = 3, open_urls = { 'left', 'right', 'third' } } } },
} }
local function wait(test) assert(vim.wait(1000, test, 5), 'agenda-overzicht bleef wachten') end
local function key(buf, name)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == name then map.callback(); return end
  end
  error('Toets ontbreekt: ' .. name)
end
local function reply()
  pending { code = 0, stdout = vim.json.encode(report) }
  wait(function() return vim.api.nvim_buf_get_name(0):find('Eigen doublures', 1, true) end)
  return vim.api.nvim_get_current_buf()
end
vim.o.hidden = false
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(source)
local lines = { 'e: B', '', '=== ARTIKEL ===', '', 'Mijn onopgeslagen kop', '', 'Mijn tekst.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, lines)
vim.api.nvim_win_set_cursor(0, { 7, 3 })
local win, cursor, tick = vim.api.nvim_get_current_win(), vim.api.nvim_win_get_cursor(0), vim.api.nvim_buf_get_changedtick(source)
local windows = #vim.api.nvim_list_wins()
agenda.eigen_doublures()
vim.api.nvim_win_set_cursor(0, { 5, 2 })
cursor = vim.api.nvim_win_get_cursor(0) -- bewaren bij tonen, niet vóór de scan
local overview = reply()
assert(vim.api.nvim_get_current_win() == win and #vim.api.nvim_list_wins() == windows, 'scan opende een extra venster')
assert(vim.api.nvim_buf_get_changedtick(source) == tick and vim.bo[source].modified)
assert(vim.bo[source].bufhidden == '' and not vim.o.hidden, 'bronopties zijn gewijzigd')
local selected
for row, line in ipairs(vim.api.nvim_buf_get_lines(overview, 0, -1, false)) do
  if line:find('[ ] Concert van ↔ Concert met · 3 artikelen', 1, true) then selected = row end
end
assert(selected, 'korte koppen of groepsgrootte ontbreken')
vim.api.nvim_win_set_cursor(win, { selected, 0 })
local opened
require('ordered_browser').open_urls = function(urls) opened = urls end
key(overview, 'o')
assert(vim.deep_equal(opened, { 'left', 'right', 'third' }), 'korte regel veranderde de browsergroep')
key(overview, 'm')
assert(pending_mark, 'beoordeling sloeg de Python-actie over')
key(overview, 'q')
assert(vim.api.nvim_get_current_buf() == source and vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), lines))
pending_mark { code = 0, stdout = '{"schema_version":1,"marked_count":1}' }
vim.wait(20, function() return false end)
assert(vim.api.nvim_get_current_buf() == source and not vim.api.nvim_buf_is_valid(overview), 'late beoordeling heropende het overzicht')

agenda.eigen_doublures(); overview = reply()
key(overview, 'r')
assert(vim.api.nvim_get_current_buf() == source and vim.tbl_contains(commands[#commands], '--include-reviewed'))
overview = reply(); key(overview, 'q')
assert(vim.api.nvim_get_current_buf() == source and #vim.api.nvim_list_wins() == windows)

-- Ook een tijdelijke bron met wipe mag bij het wisselen niet verdwijnen.
vim.bo[source].bufhidden = 'wipe'
agenda.eigen_doublures(); overview = reply()
assert(vim.api.nvim_buf_is_valid(source) and vim.bo[source].bufhidden == 'wipe')
key(overview, 'q')
assert(vim.api.nvim_get_current_buf() == source and vim.bo[source].modified)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), lines))
vim.bo[source].bufhidden = ''

vim.bo[source].readonly, vim.bo[source].modifiable = true, false
agenda.eigen_doublures(); overview = reply(); key(overview, 'q')
assert(vim.api.nvim_get_current_buf() == source and not vim.bo[source].modifiable)
vim.bo[source].readonly, vim.bo[source].modifiable = false, true

-- Een laat scanresultaat mag niet een ander inmiddels geopend artikel verdringen.
agenda.eigen_doublures()
local other = vim.api.nvim_create_buf(false, true)
vim.bo[source].bufhidden = 'hide'
vim.api.nvim_set_current_buf(other)
pending { code = 0, stdout = vim.json.encode(report) }
vim.wait(30, function() return false end)
assert(vim.api.nvim_get_current_buf() == other and #vim.api.nvim_list_wins() == windows)
assert(vim.api.nvim_buf_get_changedtick(source) == tick and vim.bo[source].modified)
print 'agenda duplicates current window: OK'
