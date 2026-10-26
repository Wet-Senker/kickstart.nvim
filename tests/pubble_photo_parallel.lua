local photos = require 'pubble_photos'
require('tests.helpers.photo_text')(photos)
local dialog = require 'user_dialog'
local requests, notices = {}, {}
vim.notify = function(message) notices[#notices + 1] = message end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return {}
end
dialog.input = function(opts, done) done(opts.default) end
dialog.confirm = function() return 1 end
local function flush() vim.wait(20, function() return false end, 5) end
local function reply(value)
  value.version = 1
  requests[#requests].done({ code = 0, stdout = vim.json.encode(value), stderr = '' }); flush()
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n' end
local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true); assert(type(map.callback) == 'function', lhs); map.callback()
end
local photo = { image_metadata_id = 731, source_article_id = 912,
  source_title = 'Bron', edition = 'B', date = '2026-10-15',
  preview_url = 'https://images.pubble.cloud/photo.jpg', caption = '', credit = 'Fotograaf' }
local function open(code)
  local source = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { 'e: ' .. code, '', '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
  vim.b[source].pending_jobs = 4
  photos.open(source)
  return source
end
for _, code in ipairs({ 'B', 'SW', 'ST', 'D', 'Z', 'K' }) do
  local source = open(code)
  local count = #requests
  vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Herschrijving klaar.' })
  reply({ query = 'biljart' })
  assert(#requests == count + 1 and requests[#requests].cmd[4] == 'search', 'suggestie vervalt door achtergrondwerk')
  vim.api.nvim_buf_set_lines(source, -1, -1, false, { '## Facebook', '', 'Nieuwe socialtekst.' })
  reply({ photos = { photo } })
  local picker = vim.api.nvim_get_current_buf()
  assert(picker ~= source, 'zoekresultaten vervallen door achtergrondwerk')
  count = #requests
  photos.open(source)
  assert(#requests == count, 'heropenen mag geen dubbele zoekronde starten')
  vim.api.nvim_win_set_cursor(0, { 5, 0 }); key('<CR>')
  assert(requests[#requests].cmd[4] == 'select')
  local original = vim.json.decode(requests[#requests].opts.stdin).markdown
  assert(original:find('Nieuwe socialtekst.', 1, true), 'selectie gebruikt niet de nieuwste tekst')
  vim.api.nvim_buf_set_lines(source, -1, -1, false, { '## Kalender', '', 'Titel: Activiteit' })
  local latest = text(source)
  reply({ markdown = 'c: Fotograaf\n' .. original })
  assert(requests[#requests].cmd[4] == 'merge', 'late fotoselectie moet veilig worden samengevoegd')
  assert(vim.json.decode(requests[#requests].opts.stdin).markdown == latest)
  assert(text(source) == latest, 'voorbereid fotoresultaat overschrijft nieuwste tekst')
  local merged = 'c: Fotograaf\n' .. latest
  reply({ markdown = merged })
  assert(text(source) == merged and vim.api.nvim_get_current_buf() == source)
  assert(vim.b[source].pending_jobs == 4, 'fotozoeker mag andere taken niet afmelden')
end

-- A rapidly changing document gets bounded local merges, never an old overwrite.
local source = open('B')
reply({ query = 'biljart' }); reply({ photos = { photo } })
vim.api.nvim_win_set_cursor(0, { 5, 0 }); key('<CR>')
for index = 1, 3 do
  local original = vim.json.decode(requests[#requests].opts.stdin).markdown
  vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Wijziging ' .. index })
  local latest = text(source)
  local before = #requests
  reply({ markdown = 'c: Fotograaf\n' .. original })
  assert(text(source) == latest, 'bij voortdurende edits niets overschrijven')
  assert(#requests == before + (index < 3 and 1 or 0), 'onbegrensde samenvoegretry')
end
key('q')

-- Publishing is still a hard boundary, including a send that starts mid-search.
source = open('B')
reply({ query = 'biljart' }); reply({ photos = { photo } })
vim.b[source].publication_in_progress = true
local count = #requests
vim.api.nvim_win_set_cursor(0, { 5, 0 }); key('<CR>')
assert(#requests == count, 'foto wijzigen tijdens publicatie mag niet')
key('q')
photos.open(source)
assert(#requests == count, 'starten tijdens daadwerkelijke publicatie mag niet')
print('pubble photo parallel: OK')
