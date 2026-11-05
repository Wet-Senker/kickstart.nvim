local ai = require 'ai_text'
local duplicates = require 'pubble_duplicates'
local notices = require 'texttools_notify'
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '', 'Biljarttoernooi', '',
  'KAMPEN - KBC houdt een toernooi.', '', '## Kalender', '',
  'Titel: Toernooi', 'Datum: 2099-11-06', 'Tijd:', 'Locatie: KBC', 'Stad: Kampen',
})
local pending = { performed = false, requested = true, complete = true, pending = true,
  missing_fields = { 'Tijd' }, message = 'Agenda wacht op Tijd. Vul aan bij ## Kalender.',
  candidates = {}, errors = {}, bron = 'kalenderblok' }
local report = { version = 1, combined = true, candidates = {}, errors = {}, history_complete = true,
  checks = { web = { requested = true, performed = true, complete = true }, agenda = pending },
  summary = { version = 1, status = 'checked',
    message = 'Doublurecontrole: web geen mogelijke doublures; agenda wacht op Tijd.',
    channels = { web = { status = 'checked', candidate_count = 0 },
      agenda = { status = 'skipped', candidate_count = 0 } } } }
local messages = {}
notices.workflow = function(message) messages[#messages + 1] = message end
duplicates.show = function() error('onvolledige agenda opende een leeg beslisscherm') end
vim.system = function(_, _, done)
  done { code = 0, stdout = vim.json.encode(report), stderr = '' }
  return {}
end
local finished
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) finished = ok end)
assert(vim.wait(1500, function() return finished ~= nil end, 5))
assert(finished and ai._duplicate_check_is_current(buf), 'webcontrole werd door ontbrekende tijd ongeldig')
assert(not ai._agenda_duplicate_is_current(buf, { 'B' }), 'wachtende agenda werd als gecontroleerd gecachet')

local reads = 0
ai._agenda_duplicate_candidates = function(_, _, done)
  reads = reads + 1
  done(vim.tbl_extend('force', pending, { version = 1 }))
end
local editing, sending
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) editing = ok end)
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) sending = ok end, nil, true)
assert(editing == true and sending == false, 'wachtstatus blokkeerde bewerken of gaf publicatie vrij')
assert(not ai._agenda_duplicate_is_current(buf, { 'B' }))
assert(table.concat(messages, '\n'):find('Agenda wacht op Tijd.', 1, true))
assert(not table.concat(messages, '\n'):find('calendar_ready', 1, true))

-- Een nieuw ingevulde tijd vraagt wél de echte controle; alleen daarna cachen.
vim.api.nvim_buf_set_lines(buf, 12, 13, false, { 'Tijd: 10:00' })
ai._agenda_duplicate_candidates = function(_, _, done)
  reads = reads + 1
  done { version = 1, performed = true, candidates = {}, errors = {}, bron = 'kalenderblok' }
end
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) sending = ok end, nil, true)
assert(sending and ai._agenda_duplicate_is_current(buf, { 'B' }))
assert(reads == 3)
ai._check_agenda_duplicates(buf, { 'B' }, function() end, nil, true)
assert(reads == 3, 'voltooide controle werd zonder wijziging opnieuw uitgevoerd')
print 'calendar duplicate pending: OK'
