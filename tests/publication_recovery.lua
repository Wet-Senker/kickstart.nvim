local recovery = require('publication_recovery')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local file = directory .. '/artikel.md'
local recovered = {
  '---', 'newspaper:', '  article_join_id: 123', 'web:',
  '  internet_article_ids: {B: 456}', '---', '',
  'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Bericht.',
}
vim.fn.writefile(recovered, file)
local original = { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Bericht.' }
local function fresh()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  return buf, vim.api.nvim_buf_get_changedtick(buf)
end

local buf, tick = fresh()
assert(recovery.restore(buf, file, tick, true), 'ongewijzigde bron werd niet hersteld')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), recovered),
  'duurzame IDs gingen verloren')
assert(vim.b[buf].failed_send_file == file, 'retrybestand ontbreekt')

-- Zowel nieuwe agenda als een latere foto-/creditkeuze blijven bij een fout
-- behouden. Het herstelbestand met de externe IDs blijft eveneens intact.
buf, tick = fresh()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
  '', '## Kalender', '', 'Titel: Nieuwe agenda', 'Datum: 2026-10-20',
})
vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
  '---', 'media:', '  selected_image:', '    image_metadata_id: 789', '---', '',
  'c: Nieuwe fotograaf', 'b: Nieuwe foto',
})
local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(not recovery.restore(buf, file, tick, true), 'late herstelactie overschreef de bron')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), current),
  'nieuwe kalender of fotokeuze verdwenen')
assert(vim.deep_equal(vim.fn.readfile(file), recovered), 'duurzame IDs werden overschreven')
assert(vim.b[buf].failed_send_conflict.file == file, 'retryconflict is niet vastgelegd')
local dialog = require('user_dialog')
dialog.confirm = function() return 2 end
assert(recovery.review_conflict(buf), 'retry kreeg geen blokkade')
assert(vim.b[buf].failed_send_conflict ~= nil, 'annuleren wiste het conflict')
assert(vim.deep_equal(vim.fn.readfile(file), recovered), 'annuleren veranderde het bestand')

dialog.confirm = function() return 1 end
assert(recovery.review_conflict(buf), 'openen startte ten onrechte de verzending')
local target = vim.api.nvim_get_current_buf()
assert(target ~= buf, 'nieuwere werkbuffer is hergebruikt/overschreven')
assert(vim.b[target].failed_send_file == file, 'herstelbuffer mist retry-ID-bestand')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(target, 0, -1, false), recovered),
  'herstelbuffer mist ID-state')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), current),
  'origineel werd bij het openen alsnog overschreven')
assert(not recovery.review_conflict(target), 'beoordeelbare herstelbuffer bleef geblokkeerd')

vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuw werk in eerder geopend herstelbestand.' })
local target_current = vim.api.nvim_buf_get_lines(target, 0, -1, false)
assert(recovery.review_conflict(buf), 'heropenen startte een verzending')
local fresh_target = vim.api.nvim_get_current_buf()
assert(fresh_target ~= target and fresh_target ~= buf, 'een gewijzigde herstelbuffer werd overschreven')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(target, 0, -1, false), target_current),
  'nieuwer werk in herstelbuffer ging verloren')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(fresh_target, 0, -1, false), recovered),
  'apart geopende diskstate mist IDs')

-- De echte aw stopt vóór ieder subprocess: de oude buffer kan nooit de
-- bewaarde Pubble-ID's overschrijven, ook niet bij herhaald drukken.
local ai = require('ai_text')
local help = ai._article_context_help(buf)
assert(help.title == 'Nieuwere wijzigingen en herstelstatus vergelijken',
  'contexthelp raadt een onveilige directe retry aan')
local old_system = vim.system
local calls = 0
vim.system = function() calls = calls + 1; error('onveilige retry') end
dialog.confirm = function() return 2 end
local ok, err = pcall(ai.pubble_send, buf)
vim.system = old_system
assert(ok, err)
assert(calls == 0, 'retryconflict startte toch AI/CMS/voorbereiding')
assert(vim.deep_equal(vim.fn.readfile(file), recovered), 'aw overschreef de herstel-ID’s')

buf, tick = fresh()
assert(not recovery.restore(buf, directory .. '/ontbreekt.md', tick, true),
  'ontbrekend herstelbestand werd geaccepteerd')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), original),
  'ontbrekend bestand wiste tekst')
vim.api.nvim_buf_delete(buf, { force = true })
assert(not recovery.restore(buf, file, tick, true), 'gesloten buffer werd hersteld')
vim.fn.delete(directory, 'rf')
print('publication recovery: OK')
