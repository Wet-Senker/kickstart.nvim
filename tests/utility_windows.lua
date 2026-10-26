-- Echte clientroutes, uitsluitend gesimuleerde Python-antwoorden.
local notifications = require 'texttools_notify'
local nav = require 'buffer_navigation'
nav.setup()
local pending
notifications.system = function(_, _, done) pending = done; return {} end
local function reply(data, raw)
  local before = vim.api.nvim_get_current_buf()
  pending { code = 0, stdout = raw or vim.json.encode(data) }
  assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() ~= before end))
  assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'hulpscherm opende toch een split')
  return vim.api.nvim_get_current_buf()
end
local function quit()
  vim.fn.maparg('q', 'n', false, true).callback()
end
vim.o.hidden = false
local source = vim.api.nvim_get_current_buf()
local text = { '=== ARTIKEL ===', '', 'Eigen onopgeslagen artikel' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, text)
local tick = vim.api.nvim_buf_get_changedtick(source)

require('agenda_bron').overzicht()
reply({})
quit()
assert(vim.api.nvim_get_current_buf() == source)
require('agenda_page').preview(source)
local preview = reply(nil, '<p>Voorbeeld</p>')
quit()
assert(vim.api.nvim_get_current_buf() == source and not vim.api.nvim_buf_is_valid(preview))

local document = '<!-- selection-start -->\n1. Eerste artikel\n<!-- selection-end -->'
require('archive_context').search(source)
local archive = reply { review = document, shown = { {} }, articles = { {} } }
vim.api.nvim_buf_set_lines(archive, 1, 2, false, { '1. Mijn selectie' })
quit()
assert(vim.api.nvim_get_current_buf() == source)
assert(vim.api.nvim_buf_get_lines(archive, 1, 2, false)[1] == '1. Mijn selectie', 'archieflijst bewerkingen verloren')

local weekly = require 'weekly_most_read'
weekly.prepare('B')
local review = reply { document = document }
weekly.generate(review)
local last = reply { edition = 'B', overview = 'Hoofdartikel', standalone = {
  { article = 'Eerste reactieartikel' }, { article = 'Tweede reactieartikel' },
} }
local bodies = {}
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buflisted and vim.api.nvim_buf_is_loaded(buf) then
    bodies[table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')] = buf
  end
end
for _, body in ipairs { 'Hoofdartikel', 'Eerste reactieartikel', 'Tweede reactieartikel' } do
  assert(bodies[body] and vim.bo[bodies[body]].bufhidden == 'hide', 'gegenereerde tekst niet bereikbaar: ' .. body)
end
assert(last == bodies['Tweede reactieartikel'])
for _ = 1, 3 do vim.cmd 'TexttoolsTerug' end
assert(vim.api.nvim_get_current_buf() == review)
vim.cmd 'TexttoolsTerug'
assert(vim.api.nvim_get_current_buf() == source and vim.bo[source].modified)
assert(vim.api.nvim_buf_get_changedtick(source) == tick and vim.deep_equal(text, vim.api.nvim_buf_get_lines(source, 0, -1, false)))
print 'utility windows: OK'
