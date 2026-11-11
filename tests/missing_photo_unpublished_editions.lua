-- Een nieuw artikel zonder foto mag als ongepubliceerd concept verder. De
-- vroege fotokeuze moet de al opgeloste editie aan de datumcontrole doorgeven.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = root

local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = root .. '/activity.json' }
require('article_recognition').evaluate = function() return {} end
require('article_recognition').rubric_decision = function() return {} end

local source = root .. '/werk/article.md'
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, source)
vim.api.nvim_set_current_buf(buf)
local lines = { 'e: B', '', '=== ARTIKEL ===', '', 'Warme jassen', '',
  'KAMPEN - Een warme jas voor wie die nodig heeft.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.fn.writefile(lines, source)

local native_system = vim.system
vim.system = function(command, _, done)
  assert(command[1]:match('pubble%-send$') and vim.tbl_contains(command, '--resolve-editions'),
    'de conceptroute startte onverwacht een externe actie')
  vim.schedule(function()
    done { code = 0, signal = 0, stderr = '', stdout = vim.json.encode {
      editions = { 'B' }, agenda_only_editions = {}, names = { 'De Brug' },
      source = 'expliciete e:-regel', has_photo = false,
      has_explicit_editions = true, text_date_check_required = true,
      link_actions = {}, skip_newspaper_editions = {}, calendar_missing = {},
    } }
  end)
  return { kill = function() end }
end

local reviewed
local dates = require 'publication_dates'
local native_review = dates.review
dates.review = function(_, _, editions, _, done)
  reviewed = vim.deepcopy(editions)
  done('cancel')
end
local native_choice = ai._missing_photo_choice
ai._missing_photo_choice = function() return 1 end

ai.pubble_send(buf, true, true)
assert(vim.wait(5000, function() return reviewed ~= nil end, 10),
  'ongepubliceerde route bereikte de datumcontrole niet')
assert(vim.deep_equal(reviewed, { 'B' }),
  'datumcontrole kreeg niet de opgeloste editie: ' .. vim.inspect(reviewed))

ai._missing_photo_choice = native_choice
dates.review = native_review
vim.system = native_system
print 'missing photo unpublished editions: OK'
