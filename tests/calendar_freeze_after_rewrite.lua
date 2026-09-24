package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'

-- Regressie: een geaccepteerd kalenderresultaat mag niet verloren gaan wanneer
-- de tekst tijdens de analyse verandert (bijv. een gelijktijdige herschrijving).
-- Het resultaat wordt bewaard en ná de lopende taak als laatste aangehecht; de
-- ## Kalender-staartsectie overleeft de herschrijving en de body blijft
-- ongemoeid. Zie VERBETERPLAN.md, casus "Reflex Volleybal" / freeze-semantiek.

ai._check_agenda_duplicates = function(_buf, _codes, done) if done then done(true) end end

local function calendar_result()
  return { code = 0, stdout = [[---
calendar:
  calendar_ready: true
  event_candidate: true
  calendar_title: Open dag
  event_date: '2099-09-19'
  start_time: '10:00'
  location_name: Buurthuis
  city: Zwolle
  calendar_body: Bezoekers zijn welkom.
---
]] }
end

-- 1. Tekst veranderde tijdens de analyse én er loopt nog een AI-taak: uitstellen.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Oude kop', '', 'Body.' })
local tick = vim.api.nvim_buf_get_changedtick(buf)
vim.b[buf].pending_jobs = 1  -- herschrijving in flight
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'Nieuwe kop' })  -- tekst wijzigt
ai._apply_articlemeta_calendar_result(buf, calendar_result(), tick)
assert(not ai._has_calendar_section(vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
  'kalender werd te vroeg aangehecht ondanks een lopende taak')
assert(vim.b[buf].pending_calendar_meta_lines ~= nil, 'geaccepteerd kalenderresultaat is niet bewaard')

-- Herschrijving herschrijft de body en rondt af; het uitgestelde blok wordt
-- nu als laatste aangehecht.
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Herschreven body.' })
ai._apply_pending_calendar_section(buf)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(lines[1] == 'Nieuwe kop', 'kalender overschreef de bewerkte kop')
assert(ai._has_calendar_section(lines), 'uitgesteld kalenderblok is niet aangehecht na de herschrijving')
assert(vim.b[buf].pending_calendar_meta_lines == nil, 'bewaard resultaat is niet opgeruimd na toepassen')

-- 2. Tekst veranderde maar er loopt geen taak meer: direct aanhechten.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf2)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { 'Kop', '', 'Body.' })
local tick2 = vim.api.nvim_buf_get_changedtick(buf2)
vim.b[buf2].pending_jobs = 0
vim.api.nvim_buf_set_lines(buf2, 2, 3, false, { 'Body gewijzigd.' })
ai._apply_articlemeta_calendar_result(buf2, calendar_result(), tick2)
local lines2 = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
assert(lines2[3] == 'Body gewijzigd.', 'directe aanhechting overschreef de bewerkte body')
assert(ai._has_calendar_section(lines2),
  'kalender werd niet direct aangehecht toen er geen taak liep')

-- 3. Ongewijzigde tekst blijft direct toepassen (happy path onveranderd).
local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf3)
vim.api.nvim_buf_set_lines(buf3, 0, -1, false, { 'Kop', '', 'Body.' })
local tick3 = vim.api.nvim_buf_get_changedtick(buf3)
ai._apply_articlemeta_calendar_result(buf3, calendar_result(), tick3)
assert(ai._has_calendar_section(vim.api.nvim_buf_get_lines(buf3, 0, -1, false)),
  'happy path hechtte de kalender niet direct aan')

print 'calendar freeze after rewrite: OK'
