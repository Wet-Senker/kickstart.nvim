local recovery = require('publication_recovery')
local revisions = require('buffer_revision')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = directory
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(source, directory .. '/werk/bron.md')
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Oude tekst.' })
local revision = revisions.capture(source)
local file = directory .. '/status.md'
vim.fn.writefile({ '---', 'newspaper: {article_join_id: 123}', '---', '',
  '=== ARTIKEL ===', '', 'Kop', '', 'Oude tekst.' }, file)
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere tekst.' })
assert(not recovery.restore(source, file, revision, true))
local calls, pending = 0
require('user_dialog').confirm_async = function(_, _, _, _, done, opts)
  calls = calls + 1; pending = done
  assert(opts.source_buf == source, 'herstelvraag verloor de bron')
end
vim.system = function() error('herstelreview mag geen subprocess starten') end
assert(recovery.review_conflict(source) and calls == 1, 'herstelreview blokkeerde of startte niet')
assert(recovery.review_conflict(source) and calls == 1, 'dubbele aw opende tweede vraag')
pending(0)
assert(vim.b[source].failed_send_conflict, 'Escape hief de herstelblokkade op')
assert(recovery.review_conflict(source) and calls == 2)
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nog een eigen toevoeging.' })
local current = vim.api.nvim_buf_get_lines(source, 0, -1, false)
pending(1)
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), current), 'asynchrone keuze overschreef nieuwer werk')
assert(vim.b[vim.api.nvim_get_current_buf()].failed_send_file == file, 'herstelbestand werd niet geopend')
assert(recovery.review_conflict(source) and calls == 3)
vim.api.nvim_buf_delete(source, { force = true })
pending(1) -- Een gesloten bron is geen toestemming om een andere te gebruiken.
vim.fn.delete(directory, 'rf')
print('publication recovery async: OK')
