local photos = require 'pubble_photos'
local dialog = require 'user_dialog'
local browser = require 'ordered_browser'

local requests, opened = {}, {}
local diagnostics = {}
require('workflow_log').diagnostic = function(_, action, detail)
  diagnostics[#diagnostics + 1] = { action = action, detail = detail }
end
vim.notify = function() end
vim.system = function(cmd, opts, callback)
  requests[#requests + 1] = { cmd = cmd, opts = opts, callback = callback }
  return {}
end
local tag_prompts = {}
dialog.input = function(opts, done)
  if (opts.description or ''):find('Vul alleen de tags', 1, true) then
    tag_prompts[#tag_prompts + 1] = opts
    done('plant, aarde, natuur')
  else done(opts.default) end
end
browser.open_urls = function(urls)
  opened[#opened + 1] = urls[1]
  return true
end

local function reply(data)
  data.version = data.version or 1
  requests[#requests].callback({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end

local function key(lhs)
  local map = vim.fn.maparg(lhs, 'n', false, true)
  assert(type(map.callback) == 'function', 'mapping ontbreekt: ' .. lhs)
  map.callback()
end

local path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' }, path)
vim.cmd('edit ' .. vim.fn.fnameescape(path))
local source = vim.api.nvim_get_current_buf()
local review = vim.api.nvim_create_buf(true, false)
vim.bo[review].buftype = 'acwrite'
vim.bo[review].bufhidden = 'hide'
vim.b[review].edition_source_buf = source
vim.b[review].edition_code = 'SW'
vim.api.nvim_buf_set_lines(review, 0, -1, false, { 'Krantkop', '', 'Goedgekeurde kranttekst.' })
vim.api.nvim_set_current_buf(review)
photos.open(review)
assert(requests[#requests].opts.stdin:find('=== ARTIKEL ===', 1, true), 'AI-stock moet hoofddocument gebruiken')
reply({ editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen' })
reply({
  photos = {}, candidates = {}, source = 'both', next_offset = vim.NIL,
  fields = { source = 'both', subject = 'plant', place = 'Kampen', exclude = '' },
  editor_text = 'Bron: Beide\nOnderwerp: plant\nPlaats: Kampen', query_strategy = 2,
})

key('a')
assert(requests[#requests].cmd[4] == 'ai-prompt')
assert(requests[#requests].opts.stdin:find('Kop', 1, true))
reply({ prompt = 'VEILIGE STOCKPROMPT', chatgpt_url = 'https://chatgpt.com/' })
assert(requests[#requests].cmd[4] == 'ai-inbox-baseline')
reply({ baseline = {} })
assert(vim.fn.getreg('"') == 'VEILIGE STOCKPROMPT')
assert(opened[#opened] == 'https://chatgpt.com/')

key('i')
assert(requests[#requests].cmd[4] == 'ai-inbox')
reply({ files = { { name = 'plant.png', relative_path = 'plant.png', sha256 = 'hash' },
  { name = 'plant2.png', relative_path = 'plant2.png', sha256 = 'hash2' } }, image_count = 2 })
assert(requests[#requests].cmd[4] == 'ai-import')
local payload = vim.json.decode(requests[#requests].opts.stdin)
assert(vim.fn.resolve(vim.fn.fnamemodify(payload.article_path, ':p'))
  == vim.fn.resolve(vim.fn.fnamemodify(path, ':p')), payload.article_path .. ' ~= ' .. path)
assert(payload.tags == 'plant, aarde, natuur' and #payload.files == 2)
assert(not tag_prompts[1].default:find('Bestand:', 1, true), 'geen padformulier meer')
assert(tag_prompts[1].description:find('plant2.png', 1, true))
local imported = {
  markdown = '---\nmedia:\n  stock_image:\n    filename: ai-stock.png\n    library_location_id: 24\n---\n\nb: Illustratief beeld\nc: AI-gegenereerd beeld (OpenAI)\n\n=== ARTIKEL ===\n\nKop\n\nTekst.\n',
  keywords = { 'plant', 'aarde', 'natuur' }, stock_location_id = 24, image_count = 2, batch_id = 'batch',
}
local extra = { '', '## Facebook', '', 'Nieuwere socialtekst.' }
vim.api.nvim_buf_set_lines(source, -1, -1, false, extra)
reply(imported)
assert(requests[#requests].cmd[4] == 'merge', 'AI-stock moet veilig met nieuwste tekst worden samengevoegd')
assert(vim.json.decode(requests[#requests].opts.stdin).markdown:find('Nieuwere socialtekst.', 1, true))
reply({ markdown = imported.markdown .. table.concat(extra, '\n') .. '\n' })
assert(vim.api.nvim_get_current_buf() == source)
assert(vim.api.nvim_buf_get_lines(review, 0, 1, false)[1] == 'Krantkop', 'AI-stock vervuilt krantversie')
local result = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n')
assert(result:find('library_location_id: 24', 1, true))
assert(result:find('AI%-gegenereerd beeld'))
assert(result:find('Nieuwere socialtekst.', 1, true))
assert(vim.fn.join(vim.fn.readfile(path), '\n'):find('library_location_id: 24', 1, true),
  'stockmetadata staat niet duurzaam in het werkartikel')
assert(diagnostics[#diagnostics].detail.status == 'saved')
assert(diagnostics[#diagnostics].detail.location_id == 24)
assert(diagnostics[#diagnostics].detail.keyword_count == 3)
assert(requests[#requests].cmd[4] == 'ai-import-finalize', 'originelen alleen na opgeslagen import wegzetten')
reply({ moved_count = 2 })

vim.fn.delete(path)
print('pubble AI stock: OK')
