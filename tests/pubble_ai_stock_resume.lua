local requests, tags, menus, notices, urls = {}, {}, {}, {}, {}
require('texttools_notify').workflow = function(message) notices[#notices + 1] = message end
local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local browser = require 'ordered_browser'
vim.notify = function(message) notices[#notices + 1] = message end
vim.system = function(cmd, opts, done)
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return {}
end
dialog.input = function(opts, done)
  if (opts.description or ''):find('Vul alleen de tags', 1, true) then
    tags[#tags + 1] = { opts = opts, done = done }
  else done(opts.default) end
end
dialog.select = function(items, opts, done) menus[#menus + 1] = { items = items, opts = opts, done = done } end
browser.open_urls = function(values) urls[#urls + 1] = values[1]; return true end
local function flush() vim.wait(30, function() return false end, 5) end
local function reply(value, code)
  requests[#requests].done({ code = code or 0, stdout = vim.json.encode(value), stderr = code and 'Testfout' or '' })
  flush()
end
local function key(buf, lhs)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs == lhs then map.callback(); return end
  end
  error('mapping ontbreekt: ' .. lhs)
end
local function focus()
  vim.api.nvim_exec_autocmds('FocusGained', {})
  flush()
end
local files = { { name = 'new.png', relative_path = 'new.png', sha256 = 'hash' } }
local baseline = { { 'old.png', 100, '1792073963123456789' } }
local path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' }, path)
vim.cmd('edit ' .. vim.fn.fnameescape(path))
local source = vim.api.nvim_get_current_buf()
local function open()
  photos.open(source)
  reply({ version = 2, editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen' })
  reply({ version = 2, photos = {}, fields = { source = 'both' } })
  return vim.api.nvim_get_current_buf()
end
local function launch(picker)
  key(picker, 'a')
  reply({ version = 1, prompt = 'STOCKPROMPT', chatgpt_url = 'https://chatgpt.com/' })
  assert(requests[#requests].cmd[4] == 'ai-inbox-baseline')
  reply({ version = 1, baseline = baseline })
  assert(urls[#urls] == 'https://chatgpt.com/')
end

local picker = open()
local count = #requests
focus()
assert(#requests == count, 'geen Inbox-controle zonder actieve AI-route')
launch(picker)
focus()
assert(requests[#requests].cmd[4] == 'ai-inbox')
local payload = vim.json.decode(requests[#requests].opts.stdin)
assert(payload.allow_empty == true and vim.deep_equal(payload.new_since, baseline))
local waiting = #requests
focus()
assert(#requests == waiting, 'geen dubbele gelijktijdige probe')
reply({ version = 1, files = {}, image_count = 0 })
assert(#tags == 0 and #menus == 0, 'lege Inbox opent geen fout of tags')
focus()
reply({ version = 1, files = files, image_count = 1 })
assert(#tags == 1, 'tags moeten automatisch openen na terugkeer')
count = #requests
focus()
key(picker, 'i')
assert(#requests == count, 'open formulier mag niet dubbel starten')
tags[1].done(nil)
focus()
assert(#requests == count, 'weggeklikt formulier mag niet vanzelf heropenen')
key(picker, 'i')
assert(#requests == count + 1, 'i moet het weggeklikte formulier heropenen')
reply({ version = 1, files = files })
tags[2].done('plant, aarde')
assert(requests[#requests].cmd[4] == 'ai-import')
reply({}, 1)
assert(#menus == 1 and menus[1].opts.native, 'importfout blijft zichtbaar')
menus[1].done('Opnieuw proberen')
reply({ version = 1, files = files })
assert(tags[3].opts.default == 'plant, aarde', 'tags blijven bewaard bij retry')
tags[3].done(nil)
key(picker, 'q')
count = #requests
focus()
assert(#requests == count, 'gesloten sessie blijft uit')

-- A focus return in another article must not steal its focus.
picker = open()
launch(picker)
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_win(vim.fn.bufwinid(source))
vim.api.nvim_set_current_buf(other)
flush()
count = #requests
focus()
assert(#requests == count, 'geen popup bij een ander artikel')
vim.api.nvim_set_current_win(vim.fn.bufwinid(picker))
flush()
assert(#requests == count + 1, 'terugkeer naar fotokeuze hervat controle')
local before = #tags
vim.api.nvim_set_current_win(vim.fn.bufwinid(other))
reply({ version = 1, files = files })
assert(#tags == before, 'late voorbereiding steelt geen focus van ander artikel')
vim.api.nvim_set_current_win(vim.fn.bufwinid(picker))
flush()
assert(#requests == count + 2)
key(picker, 'q')
reply({ version = 1, files = files })
assert(#tags == before, 'late callback na sluiten opent geen tags')

-- Read-only Inbox preparation survives text changes, without changing text.
picker = open()
launch(picker)
focus()
local latest = { '=== ARTIKEL ===', '', 'Nieuwere kop', '', 'Eigen wijziging.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, latest)
reply({ version = 1, files = files })
assert(#tags == before + 1 and vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), latest))
tags[#tags].done(nil)
count = #requests
key(picker, 'i')
assert(#requests == count + 1, 'i moet de nieuwste artikeltekst gebruiken')
assert(vim.json.decode(requests[#requests].opts.stdin).markdown:find('Nieuwere kop', 1, true))
reply({ version = 1, files = files })
tags[#tags].done(nil)
count = #requests
key(picker, 'q')
focus()
assert(#requests == count)

-- A failed baseline must not open ChatGPT or arm automatic checks.
picker = open()
key(picker, 'a')
reply({ version = 1, prompt = 'STOCKPROMPT', chatgpt_url = 'https://chatgpt.com/' })
local url_count = #urls
reply({}, 1)
assert(#urls == url_count)
count = #requests
focus()
assert(#requests == count)
key(picker, 'q')

for _, request in ipairs(requests) do
  assert(request.cmd[3] == 'texttools.pubble_photo_cli', 'geen AI- of publicatiecall')
end
vim.fn.delete(path)
print('pubble AI stock resume: OK')
