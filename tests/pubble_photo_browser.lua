local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local requests, opened, messages = {}, {}, {}
vim.notify = function(message) messages[#messages + 1] = message end
vim.system = function(cmd, opts, callback)
  local record = { cmd = cmd, opts = opts, callback = callback, killed = false }
  requests[#requests + 1] = record
  return { kill = function() record.killed = true end }
end
dialog.input = function(opts, done) done(opts.default) end
dialog.confirm = function() error('browser button must not ask confirmation again') end
require('ordered_browser').open_urls = function(urls) opened[#opened + 1] = urls[1]; return true end
local function flush() vim.wait(30, function() return false end, 5) end
local function reply(request, data)
  data.version = 1
  request.callback({ code = 0, stdout = vim.json.encode(data), stderr = '' }); flush()
end
local function key(k)
  local map = vim.fn.maparg(k, 'n', false, true)
  assert(type(map.callback) == 'function', k)
  map.callback()
end
local candidate = { image_metadata_id = 731, source_article_id = 912,
  source_title = 'Bron', edition = 'B', date = '2026-10-05',
  preview_url = 'https://images.pubble.cloud/example.jpg', caption = 'C', credit = 'F' }
local function start()
  local source = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(source)
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst' })
  photos.open(source)
  local editor_text = 'Bron: Beide\nOnderwerp: hond\nPlaats: Zwolle'
  reply(requests[#requests], { query = 'hond', editor_text = editor_text })
  reply(requests[#requests], { photos = { candidate }, candidates = { candidate },
    next_offset = 12, source = 'both', query_strategy = 2, editor_text = editor_text,
    fields = { source = 'both', subject = 'hond', place = 'Zwolle', exclude = '' } })
  key('p')
  local browse = requests[#requests]
  assert(browse.cmd[4] == 'browse')
  assert(vim.json.decode(browse.opts.stdin).photos[1].image_metadata_id == 731)
  return source, browse
end
local url = 'http://127.0.0.1:54321/temporary_session/'
local function event(request, data)
  data.version = 1
  request.opts.stdout(nil, vim.json.encode(data) .. '\n'); flush()
end

-- Partial JSON chunks, reopening the same overview and successful choice.
local source, browse = start()
local ready = vim.json.encode({ version = 1, event = 'ready', url = url }) .. '\n'
browse.opts.stdout(nil, ready:sub(1, 10)); flush()
assert(#opened == 0)
browse.opts.stdout(nil, ready:sub(11)); flush()
assert(opened[1] == url)
local count = #requests
key('p')
assert(#requests == count and #opened == 2, 'reuse active listener')
event(browse, { event = 'selected', image_metadata_id = 731 })
assert(browse.killed)
local selection = requests[#requests]
assert(selection.cmd[4] == 'select')
local payload = vim.json.decode(selection.opts.stdin)
assert(payload.photo.image_metadata_id == 731 and payload.markdown:find('Tekst', 1, true))
reply(selection, { markdown = 'b: C\nc: F\n\n=== ARTIKEL ===\n\nKop\n\nTekst\n' })
assert(vim.api.nvim_get_current_buf() == source)
assert(vim.api.nvim_buf_get_lines(source, 0, 1, false)[1] == 'b: C')
assert(#requests == count + 1, 'browser selection must not publish or upload')
event(browse, { event = 'selected', image_metadata_id = 731 })
assert(#requests == count + 1, 'duplicate event must be ignored')

-- Dezelfde b-toets doorloopt in NeoVim alle drie de bronnen. Iedere wissel
-- gebruikt opnieuw de gestructureerde Python-zoekactie.
source, browse = start()
for _, expected in ipairs({ "Artikelfoto's", 'Beeldbank', 'Beide' }) do
  key('b')
  local search_request = requests[#requests]
  local search_payload = vim.json.decode(search_request.opts.stdin)
  assert(search_payload.editor_text:find('Bron: ' .. expected, 1, true),
    'b schakelde niet door naar ' .. expected)
  local source_key = expected == "Artikelfoto's" and 'articles'
    or expected == 'Beeldbank' and 'images' or 'both'
  reply(search_request, { photos = { candidate }, candidates = { candidate },
    next_offset = vim.NIL, source = source_key, query_strategy = 2,
    editor_text = search_payload.editor_text,
    fields = { source = source_key, subject = 'hond', place = 'Zwolle', exclude = '' } })
end
key('q')

-- Paging in the browser refreshes the editor list; the new photo remains selectable.
source, browse = start()
local newer = vim.tbl_extend('force', candidate, { image_metadata_id = 732, caption = 'Nieuwe foto' })
event(browse, { event = 'page', page = { photos = { candidate, newer }, next_offset = vim.NIL } })
local page_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local page_text = table.concat(page_lines, '\n')
assert(page_text:find('Nieuwe foto', 1, true))
assert(page_lines[6] == '', 'tussen fotoresultaten ontbreekt een witregel')
assert(not page_text:find('Meer resultaten', 1, true), 'afgeronde zoekactie toont toch meer resultaten')
assert(not page_lines[2]:find(']p', 1, true), 'afgeronde zoekactie toont toch de meer-toets')
event(browse, { event = 'selected', image_metadata_id = 732 })
selection = requests[#requests]
assert(vim.json.decode(selection.opts.stdin).photo.image_metadata_id == 732)
reply(selection, { markdown = 'b: Nieuwe foto\nc: F\n\n=== ARTIKEL ===\n\nKop\n' })
assert(vim.api.nvim_get_current_buf() == source)

-- A changed article rejects browser events and preserves the new text.
source, browse = start()
count = #requests
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuw' })
event(browse, { event = 'selected', image_metadata_id = 731 })
assert(#requests == count and browse.killed)
assert(vim.api.nvim_buf_get_lines(source, -2, -1, false)[1] == 'Nieuw')
key('q')

-- A search/page change invalidates the old browser before its late choice.
for _, action in ipairs({ 's', ']p', 'q' }) do
  source, browse = start()
  key(action)
  assert(browse.killed)
  count = #requests
  event(browse, { event = 'ready', url = url })
  event(browse, { event = 'selected', image_metadata_id = 731 })
  assert(#requests == count)
  if action ~= 'q' then
    reply(requests[#requests], { photos = { candidate } })
    key('q')
  end
end

-- Unknown candidate cannot bypass the current page allowlist.
source, browse = start()
count = #requests
event(browse, { event = 'selected', image_metadata_id = 999 })
assert(#requests == count and browse.killed)
key('q')

-- Expiration and startup failure leave the article untouched and allow retry.
source, browse = start()
event(browse, { event = 'expired' })
assert(browse.killed)
key('p')
local failed = requests[#requests]
failed.callback({ code = 1, stderr = 'private failure', stdout = '' }); flush()
assert(not table.concat(messages):find('private failure', 1, true))
key('p')
assert(requests[#requests] ~= failed)
photos.setup()
vim.api.nvim_exec_autocmds('VimLeavePre', {})
assert(requests[#requests].killed, 'editor shutdown must stop listener')
key('q')
print('pubble browser choice: OK')
