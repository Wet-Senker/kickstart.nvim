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
      url = 'https://brugmedia.pubble.nl/articles/internet/371677',
    },
  },
}

local candidates_original = ai._agenda_duplicate_candidates
local confirm_original = ai._agenda_duplicate_confirm
ai._agenda_duplicate_candidates = function(_buf, _codes, done) done(data) end

-- Zonder editie is er niets te vergelijken: doorlopen zonder vraag.
local asked = false
ai._agenda_duplicate_confirm = function(_, _, done) asked = true; done(true) end
local doorgelopen = false
ai._check_agenda_duplicates(buf, {}, function(ok) doorgelopen = ok end)
assert(doorgelopen == true, 'zonder editie moet de flow gewoon doorlopen')
assert(asked == false, 'er is gevraagd terwijl er geen editie was')

-- Met een gelijkend item en "nee": geen agenda-item, artikel gaat door.
vim.b[buf].agenda_duplicate_check_done = nil
ai._agenda_duplicate_confirm = function(_, _, done) done(false) end
local vervolgd = false
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) vervolgd = ok end)

local tekst = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(vervolgd == true, 'het artikel moet doorgaan, ook zonder agenda-item')
assert(tekst:find('agenda: nee', 1, true), 'de weigering is niet vastgelegd')
ai._agenda_duplicate_candidates = function() error('geweigerd agenda-item werd opnieuw gecontroleerd') end
ai._agenda_duplicate_confirm = function() error('geweigerd agenda-item werd opnieuw gevraagd') end
local opnieuw_vervolgd = false
ai._check_agenda_duplicates(buf, { 'B' }, function(ok) opnieuw_vervolgd = ok end)
assert(opnieuw_vervolgd == true, 'eerder geweigerd agenda-item blokkeerde vervolg')
ai._agenda_duplicate_candidates = function(_buf, _codes, done) done(data) end

-- Escape (confirm geeft 0, hier nil) is geen weigering: niets wordt vastgelegd.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Op 8 juli.' })
ai._agenda_duplicate_confirm = function(_, _, done) done(nil) end
local na_escape = false
ai._check_agenda_duplicates(buf2, { 'B' }, function(ok) na_escape = ok end)
local tekst2 = table.concat(vim.api.nvim_buf_get_lines(buf2, 0, -1, false), '\n')
assert(na_escape == true and vim.b[buf2].agenda_review_cancelled == true,
  'sluiten moet bewerken laten doorgaan zonder automatische agenda-aanmaak')
assert(not tekst2:find('agenda: nee', 1, true), 'Escape mag geen weigering vastleggen')

-- De cache hoort bij de exacte inhoud. Ongewijzigde tekst wordt niet opnieuw
-- gelezen; zodra het kalenderblok of een datum verandert volgt een nieuwe ronde.
local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf3, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Op 8 juli.' })
local controles = 0
ai._agenda_duplicate_candidates = function(_buf, _codes, done)
  controles = controles + 1
  done({ version = 1, performed = true, bron = 'ruwe tekst', candidates = {} })
end
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
assert(controles == 1, 'ongewijzigde kalendergegevens zijn opnieuw gelezen')

vim.api.nvim_buf_set_lines(buf3, -1, -1, false, { '', '## Kalender', '', 'Titel: Open dag', 'Datum: 2026-07-08' })
ai._check_agenda_duplicates(buf3, { 'B' }, function() end)
assert(controles == 2, 'gewijzigde kalendergegevens kregen geen nieuwe controle')

-- Wie "toch aanmaken" koos, wordt bij dezelfde inhoud niet opnieuw gevraagd,
-- maar een latere wijziging maakt die toestemming bewust ongeldig.
local buf4 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf4, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Op 8 juli.' })
local kandidaat_calls = 0
ai._agenda_duplicate_candidates = function(_buf, _codes, done)
  kandidaat_calls = kandidaat_calls + 1
  done(data)
end
ai._agenda_duplicate_confirm = function(_, _, done) done(true) end
ai._check_agenda_duplicates(buf4, { 'B' }, function() end)
ai._check_agenda_duplicates(buf4, { 'B' }, function() end)
assert(kandidaat_calls == 1, 'dezelfde geaccepteerde kandidaat is opnieuw gelezen')
vim.api.nvim_buf_set_lines(buf4, -1, -1, false, { 'Extra informatie.' })
ai._check_agenda_duplicates(buf4, { 'B' }, function() end)
assert(kandidaat_calls == 2, 'gewijzigde inhoud gebruikte een oude toestemming')

-- Een open of afgebroken vraag is nog geen cache-hit. Ook na het ophalen blijft
-- de bronrevisie de grens: een laat "nee" mag geen nieuwe tekst wijzigen.
local late_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(late_buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Open dag' })
local answer, late_result
ai._agenda_duplicate_confirm = function(_, _, done) answer = done end
ai._check_agenda_duplicates(late_buf, { 'B' }, function(value) late_result = value end)
assert(answer and late_result == nil, 'agenda-controle wacht niet op beoordeling')
assert(vim.b[late_buf].agenda_duplicate_checked_fingerprint == nil, 'onbeantwoorde vraag telde als afgerond')
vim.api.nvim_buf_set_lines(late_buf, -1, -1, false, { 'Nieuwere tekst' })
answer(false)
assert(late_result == false, 'verouderd antwoord werd geaccepteerd')
assert(not table.concat(vim.api.nvim_buf_get_lines(late_buf, 0, -1, false), '\n'):find('agenda: nee', 1, true))

-- Handmatige ac is een expliciete werkopdracht, zonder automatische blokkade.
local manual_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(manual_buf)
vim.api.nvim_buf_set_lines(manual_buf, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '', 'Nieuwe activiteit', '',
  'KAMPEN - Op 9 juli begint om 10.00 uur een open dag.',
})
local start_original = ai._start_calendar_analysis
local resolver_original = ai._calendar_edition_resolver
local check_original = ai._check_agenda_duplicates
local ai_started = false
local resolver_done
local agenda_done
ai._start_calendar_analysis = function(start_buf)
  assert(start_buf == manual_buf, 'kalender-AI kreeg de verkeerde buffer')
  ai_started = true
end
ai._calendar_edition_resolver = function(resolve_buf, _text, done)
  assert(resolve_buf == manual_buf, 'editieresolver kreeg de verkeerde buffer')
  resolver_done = done
end
ai._check_agenda_duplicates = function(check_buf, codes, done)
  assert(check_buf == manual_buf and codes[1] == 'B', 'agenda-check kreeg verkeerde bestemming')
  agenda_done = done
end
ai.articlemeta_calendar_buffer()
assert(vim.wait(1500, function() return ai_started end), 'expliciete kalenderanalyse startte niet')
assert(resolver_done == nil and agenda_done == nil, 'ac bleef aan automatische doublurekeuzes hangen')
assert(ai._has_calendar_section(vim.api.nvim_buf_get_lines(manual_buf, 0, -1, false)), 'ac maakte geen invulbaar werkblok')
ai._start_calendar_analysis = start_original
ai._calendar_edition_resolver = resolver_original
ai._check_agenda_duplicates = check_original

ai._agenda_duplicate_candidates = candidates_original
ai._agenda_duplicate_confirm = confirm_original

print 'agenda duplicate check: OK'
