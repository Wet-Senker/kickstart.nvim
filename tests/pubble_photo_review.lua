local photos = require 'pubble_photos'
require('tests.helpers.photo_text')(photos)
local dialog = require 'user_dialog'
local requests = {}
vim.notify = function() end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return {}
end
dialog.input = function(opts, done) done(opts.default) end
dialog.confirm = function() return 1 end
local function reply(data)
  data.version = data.version or 1
  requests[#requests].done({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(25, function() return false end, 5)
end
local photo = { image_metadata_id = 731, source_article_id = 912,
  source_title = 'Bron', edition = 'SW', date = '2026-10-01',
  preview_url = 'https://images.pubble.cloud/photo.jpg', caption = '', credit = 'Fotograaf' }
local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(map.callback) == 'function', lhs)
  map.callback()
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

for _, code in ipairs({ 'B', 'SW', 'ST', 'D', 'Z', 'K' }) do
  local source = vim.api.nvim_create_buf(true, false)
  local original = 'e: ' .. code .. '\n\n=== ARTIKEL ===\n\nBronkop\n\nBront tekst.'
  vim.api.nvim_buf_set_lines(source, 0, -1, false, vim.split(original, '\n'))
  local review = vim.api.nvim_create_buf(true, false)
  vim.bo[review].buftype = 'acwrite'
  vim.bo[review].bufhidden = 'hide'
  vim.b[review].edition_source_buf = source
  vim.b[review].edition_code = code
  local variant = 'Kop ' .. code .. '\n\nGoedgekeurde kranttekst.'
  vim.api.nvim_buf_set_lines(review, 0, -1, false, vim.split(variant, '\n'))
  vim.api.nvim_set_current_buf(review)
  photos.open(review)
  assert(requests[#requests].opts.stdin == original .. '\n', 'zoekactie gebruikt variant i.p.v. bron')
  reply({ query = 'biljart' })
  reply({ photos = { photo } })
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  key('<CR>')
  assert(vim.json.decode(requests[#requests].opts.stdin).markdown == original .. '\n')
  local updated = 'c: Fotograaf\n\n' .. original
  reply({ markdown = updated })
  assert(text(source) == updated)
  assert(text(review) == variant, 'fotoselectie vervuilt kranttekst')
  assert(vim.b[review].edition_requires_review ~= true, 'fotokeuze trekt akkoord in')
  assert(vim.api.nvim_get_current_buf() == source)
end

-- An orphaned review buffer may never become a standalone article silently.
local orphan = vim.api.nvim_create_buf(true, false)
vim.b[orphan].edition_source_buf = 999999
local count = #requests
photos.open(orphan)
assert(#requests == count, 'ontbrekende bron moet de fotokeuze blokkeren')

print('pubble photo review: OK')
