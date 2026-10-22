-- De echte aw-hervatroute met de echte Python-datumreview. Alleen de CMS-
-- send is nep: deze test mag nooit een artikel of upload buiten de test maken.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = root
local ai = require('ai_text')
local recognition = require('article_recognition')
local activity = require('article_activity')
activity.setup { preferences = root .. '/activity.json' }
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end
local codes = { 'B', 'SW', 'ST', 'K' }
local source = root .. '/werk/article.md'
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, source)
vim.api.nvim_set_current_buf(buf)
local lines = { 'e: B, SW, ST, K', 'agenda: nee', '', '=== ARTIKEL ===', '',
  'Ov-staking gaat niet door', '', 'REGIO - De aangekondigde ov-staking gaat niet door.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.fn.writefile(lines, source)
-- Zowel een reeds beoordeelde krantvariant als een hervatting gebruikt deze
-- bewaarde planning. Direct plaatsen levert hier bewust een lege mapping.
vim.b[buf].publication_review_state = {
  editions = codes, display_dates = {}, skip_newspaper_editions = codes,
}
ai._mark_duplicate_check_done(buf)
local native_system = vim.system
local sends, reviews, menus = 0, 0, {}
local dialog = require('user_dialog')
dialog.select = function(items, options, done)
  menus[#menus + 1] = { items = items, options = options, done = done }
end
vim.system = function(command, options, done)
  if command[3] == 'texttools.publication_dates_cli' then
    reviews = reviews + 1
    return native_system(command, options, done)
  end
  assert(command[1]:match('pubble%-send$') and vim.tbl_contains(command, '--create'), 'onverwachte externe call')
  sends = sends + 1
  assert(not vim.tbl_contains(command, '--display-dates'), 'directe plaatsing kreeg een gegokte datum')
  if sends == 1 then
    -- Zoals in het stakingsartikel: metadata/social kan de gedeelde kern pas
    -- later aanleiding geven tot een datumreview. De oorspronkelijke poging
    -- heeft dan nog geen CMS-write verricht en bewaart de voorbereide tekst.
    local staged = vim.fn.readfile(command[2])
    vim.list_extend(staged, { '', '## Facebook', '', 'Vandaag gaat de staking niet door.' })
    vim.fn.writefile(staged, command[2])
    vim.schedule(function()
      done { code = 0, signal = 0, stderr = '', stdout = 'PUBBLE_RESULT_JSON: '
        .. vim.json.encode { mode = 'needs_date_review', outcome = 'failed', phases = {} } }
    end)
  else
    assert(sends == 2, 'onnodige herhaalde verzending')
    local staged = table.concat(vim.fn.readfile(command[2]), '\n')
    assert(staged:find('date_approval', 1, true), 'datumwaarschuwing werd zonder akkoord gepasseerd')
    -- Stop aan de geteste verzendgrens: geen echte CMS-call/finalisatie.
  end
  return {}
end
local function wait(test) assert(vim.wait(10000, test, 5), 'aw/datumhervatting bleef hangen') end
ai.pubble_send(buf)
wait(function() return sends == 1 and vim.b[buf].publication_in_progress == false end)
assert(reviews == 1 and #menus == 0 and not vim.b[buf].publication_date_review_pending)
assert(vim.b[buf].publication_review_state and next(vim.b[buf].publication_review_state.display_dates) == nil)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Vandaag gaat de staking', 1, true))
ai.pubble_send(buf)
wait(function() return #menus == 1 end)
assert(sends == 1 and reviews == 2, 'hervatten sloeg de inhoudelijke beoordeling over')
assert(menus[1].items[1]:find('Gecontroleerd', 1, true))
menus[1].done(menus[1].items[1])
wait(function() return sends == 2 end)
assert(reviews == 3 and not vim.b[buf].publication_date_review_pending)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('date_approval', 1, true))
vim.system = native_system
print('publication dates send: OK')
