-- De echte publicatieadapter met ingeschakeld logboek: geen Fidget, writes,
-- netwerkverkeer of doorstart bij een fout of gewijzigde artikelrevisie.
package.preload['fidget.progress'] = function() error 'artikelacties mogen geen losse Fidget-spinner starten' end
package.preload['fidget.notification'] = function() error 'artikelmeldingen mogen niet als toast verdwijnen' end
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local ai = require 'ai_text'
local original_send, native_system = ai.pubble_send, vim.system
local source = vim.api.nvim_create_buf(true, false)
local other = vim.api.nvim_create_buf(true, false)
local content = { '=== ARTIKEL ===', '', 'ZwartsluisBruist', '', 'Mijn artikeltekst.' }
vim.api.nvim_buf_set_lines(source, 0, -1, false, content)
vim.api.nvim_buf_set_lines(other, 0, -1, false, { '=== ARTIKEL ===', '', 'Ander artikel' })
vim.api.nvim_set_current_buf(other)
local callback, calls
vim.system = function(command, _, done)
  assert(vim.tbl_contains(command, '--merge-cached-metadata'), 'test startte echte publicatie')
  calls = (calls or 0) + 1
  callback = done
  return { kill = function() end }
end
local function start()
  vim.b[source].cached_metadata = { '---', 'newspaper: {working_title: Kop}', '---' }
  vim.b[source].cached_metadata_source = table.concat(content, '\n')
  original_send(source)
  assert(vim.b[source].metadata_merge_pending == true, 'metadata-opdracht niet gestart')
  assert(next(activity.snapshot(source).tasks), 'lopende opdracht niet geregistreerd')
  if calls == 1 then assert(activity.statusline(source):find('Bezig', 1, true), 'lopende opdracht onzichtbaar') end
end
local function finish(result)
  callback(result)
  assert(vim.wait(1000, function() return not vim.b[source].metadata_merge_pending and (vim.b[source].pending_jobs or 0) == 0 end), 'opdracht bleef hangen')
end
start()
finish { code = 2, stderr = 'onbekende CLI-optie', stdout = '' }
assert(calls == 1, 'fout startte extra subprocessen')
assert(activity.statusline(source):find('Fout', 1, true), 'procesfout werd als succes getoond')
local entries = activity.snapshot(source).entries
assert(entries[#entries].message:find('Metadata samenvoegen mislukt', 1, true), 'menselijke foutdiagnose ontbreekt')
assert(vim.deep_equal(content, vim.api.nvim_buf_get_lines(source, 0, -1, false)), 'fout wijzigde het artikel')
assert(not vim.inspect(activity.snapshot(other)):find('onbekende CLI-optie', 1, true), 'fout verscheen bij ander artikel')

-- Een nieuwere bewerking blijft intact en het succes van het subprocess mag
-- haar verwerping niet alsnog als "tekst toegepast" presenteren.
local resumed = 0
ai.pubble_send = function() resumed = resumed + 1 end
start()
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere tekst.' })
finish { code = 0, stderr = '', stdout = 'Verouderde tekst' }
assert(resumed == 0 and calls == 2, 'verworpen resultaat hervatte publicatie')
entries = activity.snapshot(source).entries
assert(entries[#entries].message:find('Tekst gewijzigd', 1, true), 'verwerping is niet leesbaar')
assert(vim.api.nvim_buf_get_lines(source, -2, -1, false)[1] == 'Nieuwere tekst.', 'late callback overschreef nieuwere tekst')
assert(next(activity.snapshot(source).tasks) == nil, 'afgeronde taak bleef in statusbalk')

-- De buffer mag veranderen terwijl de bron ondertussen verborgen is.
-- Alleen een echte, geaccepteerde merge mag de bestaande workflow hervatten.
start()
local current = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), '\n')
finish { code = 0, stderr = '', stdout = current }
assert(resumed == 1 and calls == 3, 'geldige merge hervatte de bestaande workflow niet exact eenmaal')
assert(not activity.snapshot(source).attention, 'geslaagde herhaling liet de oude metadatafout staan')
assert(vim.api.nvim_get_current_buf() == other, 'logboek stal focus van het andere artikel')
assert(not vim.b[source].cached_metadata, 'geldige cache bleef staan')
ai.pubble_send, vim.system = original_send, native_system
print 'article activity workflow: OK'
