-- Agenda-doublurecontrole vóór iedere verwerking.
local ai = require 'ai_text'

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'Open dag op de zorgboerderij',
  '',
  'KAMPEN - Op 8 juli houdt De Groene Hoeve een open dag.',
})

local data = {
  version = 1,
  performed = true,
  bron = 'ruwe tekst',
  candidates = {
    {
      editie = 'B',
      bestaand_id = '371677',
      bestaand_titel = 'Open dag zorgboerderij',
      bestaand_datum = '2026-07-08',
      bestaand_locatie = 'De Groene Hoeve',
      url = 'https://brugmedia.pubble.dev/articles/internet/371677',
    },
  },
}

local candidates_original = ai._agenda_duplicate_candidates
local confirm_original = ai._agenda_duplicate_confirm
ai._agenda_duplicate_candidates = function(_buf, _codes, done) done(data) end

-- Zonder editie is er niets te vergelijken: doorlopen zonder vraag.
local asked = false
ai._agenda_duplicate_confirm = function() asked = true return true end
local doorgelopen = false
ai._check_agenda_duplicates(buf, {}, function(ok) doorgelopen = ok end)
assert(doorgelopen == true, 'zonder editie moet de flow gewoon doorlopen')
assert(asked == false, 'er is gevraagd terwijl er geen editie was')

-- Met een gelijkend item en "nee": geen agenda-item, artikel gaat door.
vim.b[buf].agenda_duplicate_check_done = nil
ai._agenda_duplicate_confirm = function() return false end
local vervolgd = false
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) vervolgd = ok end)

local tekst = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(vervolgd == true, 'het artikel moet doorgaan, ook zonder agenda-item')
assert(tekst:find('agenda: nee', 1, true), 'de weigering is niet vastgelegd')

-- Escape (confirm geeft 0, hier nil) is geen weigering: niets wordt vastgelegd.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Op 8 juli.' })
ai._agenda_duplicate_confirm = function() return nil end
local na_escape = false
ai._check_agenda_duplicates(buf2, { 'B' }, function(ok) na_escape = ok end)
local tekst2 = table.concat(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), '\n')
assert(na_escape == true, 'de flow moet ook na Escape doorlopen')
assert(not tekst2:find('agenda: nee', 1, true), 'Escape mag geen weigering vastleggen')

-- Na een vergelijking op ruwe tekst mag er nog een scherpe ronde komen: zodra
-- het kalenderblok bestaat zijn titel en locatie opgeschoond.
local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf3, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Op 8 juli.' })
vim.b[buf3].agenda_duplicate_check_source = 'ruwe tekst'
local tweede_ronde = false
ai._agenda_duplicate_confirm = function() tweede_ronde = true return nil end
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
assert(tweede_ronde == true, 'na ruwe tekst moet een scherpe ronde mogelijk blijven')

-- Is er al mét het kalenderblok vergeleken, dan is de vraag beantwoord.
vim.b[buf3].agenda_duplicate_check_source = 'kalenderblok'
local derde_ronde = false
ai._agenda_duplicate_confirm = function() derde_ronde = true return nil end
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
assert(derde_ronde == false, 'na het kalenderblok mag er niet nog eens gevraagd worden')

-- Wie al "toch aanmaken" koos, wordt niet nog eens lastiggevallen.
vim.b[buf3].agenda_duplicate_check_source = 'ruwe tekst'
vim.b[buf3].agenda_duplicate_accepted = true
local nogmaals = false
ai._agenda_duplicate_confirm = function() nogmaals = true return nil end
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
assert(nogmaals == false, 'een gemaakte keuze mag niet opnieuw gevraagd worden')

ai._agenda_duplicate_candidates = candidates_original
ai._agenda_duplicate_confirm = confirm_original

print 'agenda duplicate check: OK'
