local ai = require 'ai_text'
local article_recognition = require 'article_recognition'
ai._column_recognition_runner = function(_, _, callback) callback({}) end

-- Regressie: handmatig <leader>ac moet bij veel losse datums dezelfde
-- datum-bewuste vraag stellen als het automatische detectiepad. Voorheen sloeg
-- het handmatige pad die vraag over en zakte het na een tekstwijziging stil
-- terug op één kalenderitem (zie VERBETERPLAN.md, casus "Reflex Volleybal").

local function many_dates_text()
  return [[
maandag 24 augustus

Concert in de kerk

20:00 uur | Buitenkerk

dinsdag 25 augustus

Tweede activiteit

woensdag 26 augustus

Derde activiteit

donderdag 27 augustus

Vierde activiteit
]]
end

local text = many_dates_text()
assert(article_recognition.calendar_date_count(text) > 3, 'testtekst moet meer dan drie datums bevatten')

-- Stubs: geen AI, geen netwerk. Alle drie worden via M aangeroepen en zijn dus
-- vervangbaar op de gedeelde tabel.
local original_start = ai._start_calendar_analysis
local original_confirm = ai._calendar_date_confirm
local original_resolver = ai._calendar_edition_resolver
local original_dup = ai._check_agenda_duplicates

local started
ai._start_calendar_analysis = function(_) started = true end
ai._calendar_edition_resolver = function(_, _, cb) cb({ editions = {} }) end
ai._check_agenda_duplicates = function(_, _, cb) if cb then cb() end end

local function fresh_buf(lines_text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(lines_text, '\n', { plain = true }))
  vim.api.nvim_set_current_buf(buf)
  return buf
end

-- 1. Veel datums + Ja: de datum-vraag komt en de analyse start.
local asked
ai._calendar_date_confirm = function(date_count) asked = date_count; return 1 end
fresh_buf(text)
started = nil
ai.articlemeta_calendar_buffer()
assert(asked and asked > 3, 'handmatige <leader>ac stelde de datum-vraag niet')
assert(started == true, 'na Ja moet de kalenderanalyse starten')

-- 2. Veel datums + Nee: geen analyse, wel persistente afwijzing.
ai._calendar_date_confirm = function(_) return 2 end
local rejected_buf = fresh_buf(text)
started = nil
ai.articlemeta_calendar_buffer()
assert(started ~= true, 'na Nee mag de kalenderanalyse niet starten')
local lines = vim.api.nvim_buf_get_lines(rejected_buf, 0, -1, false)
assert(lines[1] == 'agenda: nee', 'Nee moet agenda: nee in de buffer zetten')

-- 3. Weinig datums: geen vraag, analyse start direct (ongewijzigd gedrag).
ai._calendar_date_confirm = function(_) asked = 'niet stellen'; return 1 end
fresh_buf('Concert op zaterdag 3 oktober om 20.00 uur in de Buitenkerk.')
asked = nil
started = nil
ai.articlemeta_calendar_buffer()
assert(asked == nil, 'bij weinig datums mag geen datum-vraag verschijnen')
assert(started == true, 'bij weinig datums moet de analyse gewoon starten')

ai._start_calendar_analysis = original_start
ai._calendar_date_confirm = original_confirm
ai._calendar_edition_resolver = original_resolver
ai._check_agenda_duplicates = original_dup
print 'calendar manual many dates: OK'
