local notifications = require 'texttools_notify'
local requests, urls, notices = {}, {}, {}
local native_system = vim.system
vim.notify = function(message) notices[#notices + 1] = message end
notifications.workflow = function(message) notices[#notices + 1] = message end
local photos = require 'pubble_photos'
require('ordered_browser').open_urls = function(values) urls[#urls + 1] = values[1]; return true end
require('user_dialog').input = function(options, done) done(options.default) end
notifications.system = function(cmd, options, done)
  if cmd[4] == 'select' or cmd[4] == 'merge' then
    return native_system(cmd, options, vim.schedule_wrap(done)) -- real local Python action, no HTTP
  end
  local request = { cmd = cmd, options = options, done = done }
  requests[#requests + 1] = request
  return { kill = function() request.killed = true end }
end
local function settle() vim.wait(30, function() return false end, 5) end
local function reply(data)
  requests[#requests].done { code = 0, stdout = vim.json.encode(vim.tbl_extend('force', {version = 2}, data)) }
  settle()
end
local function event(request, data)
  data.version = 1
  request.options.stdout(nil, vim.json.encode(data) .. '\n')
  settle()
end
local source = vim.api.nvim_get_current_buf()
local content = { 'e: B', '', '=== ARTIKEL ===', '', 'Mijn artikel', '', 'KAMPEN - Mijn eigen tekst.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, content)
vim.api.nvim_win_set_cursor(0, { 7, 5 })
local tick, win = vim.api.nvim_buf_get_changedtick(source), vim.api.nvim_get_current_win()
local photo = { image_metadata_id = 731, source_article_id = 912, source_title = 'Archiefbron',
  edition = 'B', date = '2026-10-01', preview_url = 'https://images.pubble.cloud/test.jpg',
  caption = 'Oud bijschrift', credit = 'Fotograaf' }
photos.open()
reply { editor_text = 'Bron: Beide\nZoekwoorden: fiets' }
reply { photos = {photo}, candidates = {photo}, source = 'both', fields = {source='both', subject='fiets'} }
local browse = requests[#requests]
assert(browse.cmd[4] == 'browse', 'browser niet automatisch gestart')
assert(browse.options.texttools_activity.tracked, 'wachtende browser toont een eindeloze werktak')
assert(vim.api.nvim_get_current_buf() == source and vim.api.nvim_get_current_win() == win)
assert(#vim.api.nvim_tabpage_list_wins(0) == 1 and #vim.api.nvim_list_bufs() == 1, 'ongevraagde resultatenbuffer')
assert(vim.api.nvim_buf_get_changedtick(source) == tick and vim.api.nvim_win_get_cursor(win)[2] == 5)
local url = 'http://127.0.0.1:54321/photo_session/'
event(browse, { event='ready', url=url })
assert(urls[1] == url)
local count = #requests
photos.open()
assert(#requests == count and #urls == 2, 'heropenen zoekt of start een tweede server')
local newer = vim.tbl_extend('force', photo, {image_metadata_id=732})
event(browse, {event='page', page={photos={newer}}})
assert(vim.api.nvim_get_current_buf() == source and vim.api.nvim_buf_get_changedtick(source) == tick)
vim.api.nvim_buf_set_lines(source, -1, -1, false, {'Nieuwere eigen tekst.'})
event(browse, {event='selected', image_metadata_id=732})
assert(vim.wait(3000, function()
  return table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n'):find('\nbeeld: %[Archieffoto') ~= nil
end), 'gedeelde selectieactie plaatste geen beeldregel')
local selected = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n')
assert(selected:find('image_metadata_id: 732', 1, true), 'browserselectie koos niet de nieuwe foto')
assert(selected:find('Nieuwere eigen tekst.', 1, true) and selected:find('c: Fotograaf', 1, true))
assert(not selected:find('b: Oud bijschrift', 1, true), 'oud bijschrift overgenomen')
local ai = require 'ai_text'
local marker = selected:match('\n(beeld: [^\n]+)')
local controls = ai._add_media_controls({marker}, {photographer='Foto: Fotograaf'})
assert(#controls == 2, 'beeldregel verdrong een echte fotocredit bij herschrijven')
assert(browse.killed and vim.api.nvim_get_current_buf() == source)
count = #requests
event(browse, {event='selected', image_metadata_id=731})
assert(#requests == count, 'late browserkeuze herleefde')

-- Geen verborgen tekstscherm bij een lege zoekactie of een browserfout.
photos.open()
reply { editor_text='Bron: Beide\nZoekwoorden: fiets' }
reply { photos={}, source='both', fields={source='both', subject='fiets'} }
browse = requests[#requests]
assert(browse.cmd[4] == 'browse')
event(browse, {event='expired'})
photos.open()
local retry = requests[#requests]
assert(retry ~= browse and retry.cmd[4] == 'browse')
retry.done {code=1, stderr='private details'}
settle()
assert(vim.api.nvim_get_current_buf() == source and #vim.api.nvim_tabpage_list_wins(0) == 1)
assert(not table.concat(notices):find('private details', 1, true))
assert(table.concat(notices):find('PubbleFotoTekst', 1, true), 'browserfout mist vervolgstap')
count = #requests
photos.open(source, {text=true})
local fallback = vim.api.nvim_get_current_buf()
assert(fallback ~= source and #requests == count, 'expliciete tekstfallback deed een nieuwe zoekscan')
vim.fn.maparg('q', 'n', false, true).callback()
assert(vim.api.nvim_get_current_buf() == source)
print 'direct photo browser: OK'
