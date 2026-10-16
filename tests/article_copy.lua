local copy = require('article_copy').setup()
local original = vim.system
local calls, pending = {}, {}
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(source)
local input = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nEerste tekst.'
vim.api.nvim_buf_set_lines(source, 0, -1, false, vim.split(input, '\n'))
vim.b[source].edition_source_buf = 123
vim.b[source].pubble_send_started = true
vim.b[source].weekend_batch_id = 'oud'
local tick = vim.api.nvim_buf_get_changedtick(source)
vim.system = function(cmd, opts, done)
  calls[#calls + 1] = { cmd = cmd, opts = opts }
  pending[#pending + 1] = done
  return { kill = function() end }
end
local output = 'e:\n\n=== ARTIKEL ===\n\nKop\n\nEerste tekst.\n\n---\n\n## Niet voor publicatie\n\n> Kopie voor een andere krant.\n'
local function result()
  return { code = 0, stdout = vim.json.encode({ contract_version = 1, label = 'Kopie', markdown = output }), stderr = '' }
end
local function drain()
  local done = false
  vim.schedule(function() done = true end)
  assert(vim.wait(2000, function() return done end, 10))
end
vim.cmd('ArtikelKopie')
assert(calls[1].cmd[3] == 'texttools.article_copy_cli')
assert(calls[1].opts.stdin == input)
pending[1](result())
drain()
local copied = vim.api.nvim_get_current_buf()
assert(copied ~= source)
assert(vim.api.nvim_buf_get_name(copied):find('Kopie-', 1, true))
assert(vim.bo[copied].buftype == '' and vim.bo[copied].modified)
assert(vim.b[copied].edition_source_buf == nil)
assert(vim.b[copied].pubble_send_started == nil and vim.b[copied].weekend_batch_id == nil)
assert(vim.api.nvim_buf_get_changedtick(source) == tick)
assert(table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n') == input)
-- :w op de nieuwe buffer is een gewone bestandsschrijfactie, geen reviewupdate.
assert(#vim.api.nvim_get_autocmds({ event = 'BufWriteCmd', buffer = copied }) == 0)
-- Een late callback na een bronwijziging opent geen kopie.
vim.api.nvim_set_current_buf(source)
copy.copy()
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere tekst.' })
pending[2](result())
drain()
assert(vim.api.nvim_get_current_buf() == source)
-- Een nieuwere aanvraag wint; de oudere callback wordt weggegooid.
copy.copy()
copy.copy()
pending[3](result())
drain()
assert(vim.api.nvim_get_current_buf() == source)
pending[4]({ code = 1, stderr = 'Bewuste fout', stdout = '' })
drain()
assert(vim.api.nvim_get_current_buf() == source)
copy.copy()
pending[5]({ code = 0, stdout = '{}', stderr = '' })
drain()
assert(vim.api.nvim_get_current_buf() == source)
-- Ook gesloten bronbuffers krijgen geen laat resultaat.
copy.copy()
vim.api.nvim_buf_delete(source, { force = true })
local current = vim.api.nvim_get_current_buf()
pending[6](result())
drain()
assert(vim.api.nvim_get_current_buf() == current)
vim.system = original
-- Echte CLI-integratie vanuit een onopgeslagen krantreview; geen AI/netwerk.
local review = vim.api.nvim_create_buf(true, true)
vim.bo[review].buftype = 'acwrite'
vim.api.nvim_set_current_buf(review)
local review_text = '## Mijn krantkop\n\nEen handmatige correctie.\n\n## Gewone tussenkop\n\nNog een alinea.\n\n---\n\n## Facebook\nOude post.'
vim.api.nvim_buf_set_lines(review, 0, -1, false, vim.split(review_text, '\n'))
vim.b[review].edition_source_buf = copied
copy.copy()
assert(vim.wait(10000, function() return vim.api.nvim_get_current_buf() ~= review end, 20))
local real_copy = vim.api.nvim_get_current_buf()
local real_text = table.concat(vim.api.nvim_buf_get_lines(real_copy, 0, -1, false), '\n')
assert(real_text:find('## Mijn krantkop', 1, true))
assert(real_text:find('## Gewone tussenkop', 1, true))
assert(real_text:find('Een handmatige correctie.', 1, true))
assert(not real_text:find('Oude post.', 1, true))
assert(real_text:find('Kopie voor een andere krant.', 1, true))
assert(vim.b[real_copy].edition_source_buf == nil)
assert(table.concat(vim.api.nvim_buf_get_lines(review, 0, -1, false), '\n') == review_text)
print('article copy: OK')
