local messages = {}
package.loaded['agenda_menu'] = nil
package.loaded['texttools_notify'] = {
  workflow = function(message) table.insert(messages, message) end,
}
package.loaded['ordered_browser'] = {
  open_urls = function() error('test mag geen browser openen') end,
}
local module = require 'agenda_menu'
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Concert', '', 'Artikeltekst.', '',
  '## Kalender', '', 'Titel: Concert', 'Stad: Dronten',
})
vim.fn.confirm = function() return 1 end
local original_system = vim.system
local calls = 0
vim.system = function(command, _, callback)
  calls = calls + 1
  assert(command[5] == 'artikel-plaatsen', 'verkeerde kernactie')
  callback { code = 0, stdout = vim.json.encode {
    status = 'created', created = { { title = 'Concert Dronten', calendar_id = 887 } },
    skipped = { { title = 'Concert Almere', city = 'Almere' } },
  }, stderr = '' }
  return { kill = function() end }
end
module.artikel_plaatsen(buf)
assert(vim.wait(1000, function() return vim.b[buf].article_calendar_status == 'created' end, 10),
  'lokale plaatsing werd niet voltooid')
assert(calls == 1, 'extra subprocess gestart')
local output = table.concat(messages, '\n')
assert(output:find('Concert Almere (Almere)', 1, true), 'overgeslagen item niet toegelicht')
assert(output:find('gezamenlijke verspreidingsgebied', 1, true), 'reden overslaan ontbreekt')
assert(output:find('1 agenda-item(s) geplaatst', 1, true), 'succes van lokale item ontbreekt')
assert(vim.bo[buf].modifiable, 'buffer bleef geblokkeerd')
vim.system = original_system
print 'article calendar coverage: OK'
