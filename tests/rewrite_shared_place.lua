package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require 'ai_text'
local review = ai._edition_review
local dialog = require 'user_dialog'
local original_system, original_select = vim.system, dialog.select
local source = 'Lichtjestour opent inschrijving\n\n'
  .. 'DRONTEN - Verlichte trekkers rijden op 11 december 2026 door Swifterbant, '
  .. 'op 12 december 2026 door Biddinghuizen en op 19 december 2026 door Dronten. '
  .. 'Stichting De IJsvogel organiseert de dorpsavond in Biddinghuizen.'
local variants = {
  D = 'Lichtjestour door drie dorpen\n\n**DRONTEN - De Lichtjestour rijdt door '
    .. 'Dronten, Biddinghuizen en Swifterbant.**\n\nDe drie dorpen delen de inschrijving.',
  Z = 'Lichtjestour in Biddinghuizen\n\n**BIDDINGHUIZEN - De Lichtjestour rijdt '
    .. 'op 12 december door Biddinghuizen.**\n\nStichting De IJsvogel organiseert '
    .. 'de dorpsavond. De andere routes zijn in Swifterbant en Dronten.',
}
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split('e: D, Z\n\n=== ARTIKEL ===\n\n' .. source, '\n'))
ai._mark_duplicate_check_done(buf)
vim.b[buf].calendar_autodetect_suppressed = true
ai._capture_import_baseline(buf)

local requested, menu_count = {}, 0
dialog.select = function(items, opts, done)
  menu_count = menu_count + 1
  assert(items[1].index == 2, 'gericht advies staat niet bovenaan')
  assert(opts.prompt:find('Biddinghuizen →', 1, true), 'gedeelde plaats ontbreekt in motivatie')
  assert(opts.prompt:find('Zeewolde Actueel', 1, true), 'lokale Z-taak ontbreekt in motivatie')
  assert(next(requested) == nil, 'AI startte voor de keuze')
  done(items[1])
end
vim.system = function(command, opts, callback)
  if command[2] == 'krantversie' or command[2] == 'krantversie_algemeen' then
    assert(command[2] == 'krantversie', 'gedeelde plaats kreeg algemene rewrite')
    assert(opts.stdin == source, 'taak gebruikte niet het origineel')
    assert(vim.tbl_contains(command, '--optional-local-angle'), 'lokale afwijsoptie ontbreekt')
    local code = command[4]
    assert(variants[code] and not requested[code], 'dubbele of onbekende AI-taak')
    requested[code] = command
    callback { code = 0, stdout = variants[code], stderr = '' }
    return { kill = function() end }
  end
  if command[1] == 'bash' then error('overbodige tussenrewrite') end
  if command[2] == 'tussenkopjes' or command[2] == 'streamer' then error('extra opmaakcall') end
  -- Resolver, strategie, bronbewaking en workspace blijven de echte Python-kern.
  if not callback or command[2] == 'inspect' or vim.tbl_contains(command, '--resolve-editions')
      or command[2] == '-m' then return original_system(command, opts, callback) end
  callback { code = 0, stdout = '', stderr = '' }
  return { kill = function() end }
end
ai.rewrite_article_buffer()
assert(vim.wait(5000, function() return review._review_buffers[buf] ~= nil end, 10), 'review bleef hangen')
assert(menu_count == 1 and vim.tbl_count(requested) == 2, 'niet precies één keuze en twee rewrites')
local entries = review._review_buffers[buf]
assert(vim.tbl_count(entries) == 2 and entries.D and entries.Z, 'aparte lokale review ontbreekt')
local zeewolde = table.concat(vim.api.nvim_buf_get_lines(entries.Z, 0, -1, false), '\n')
assert(zeewolde:find('BIDDINGHUIZEN -', 1, true), 'Z-invalshoek ging verloren in review')
review.close(buf, true)
vim.system, dialog.select = original_system, original_select
print 'rewrite shared place: OK'
