package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
local lines = {
  'Foto: Marcel Lennartz', '', '=== ARTIKEL ===', '',
  'Tröckener Kecks komt naar Hedon', '', 'ZWOLLE - De band keert terug.',
  '', '---', '', '## Niet voor publicatie', '',
  '> *Niet voor publicatie:*', '> Fotograaf Marcel Lennartz',
  '> Aanvang: 20:30 uur', '> Entree: €38,50',
  '> ## Facebook', '> Bronkopje, geen socialpost.',
}
assert(ai._editorial_body_text(lines) == 'Tröckener Kecks komt naar Hedon\n\nZWOLLE - De band keert terug.',
  'bronnotities zitten in de herschrijf-/goedkeuringsbody')
local first = ai._upsert_tail_section(lines, 'Facebook', 'Nieuwe socialpost.')
local second = ai._upsert_tail_section(first, 'LinkedIn', 'Zakelijke socialpost.')
local text = table.concat(second, '\n')
assert(text:find('## LinkedIn', 1, true) < text:find('## Niet voor publicatie', 1, true),
  'bronnotities staan niet onder alle gegenereerde secties')
assert(text:find('> Aanvang: 20:30 uur', 1, true) and text:find('> Entree: €38,50', 1, true),
  'praktische broninformatie verdween')
assert(text:find('> ## Facebook', 1, true), 'bronkopje werd werksectie')
local replaced = ai._upsert_tail_section(second, 'Facebook', 'Vervangen socialpost.')
assert(table.concat(replaced, '\n'):find('> Fotograaf Marcel Lennartz', 1, true),
  'socialvervanging beschadigde bronnotities')
assert(ai._editorial_body_text(replaced) == ai._editorial_body_text(lines))

-- Een concertomschrijving die uitsluitend in de noot staat mag geen extra
-- automatische kalender-AI of datumkeuze veroorzaken.
local quiet = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(quiet, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Kop', '', 'Een algemeen bericht.', '',
  '## Niet voor publicatie', '', '> Concert op vrijdag 5 november 2027.',
  '> Aanvang: 20:30 uur in theater Hedon. Entree €38,50.',
})
local analysis = ai._start_calendar_analysis
ai._start_calendar_analysis = function() error('privé-noot startte kalender-AI') end
local raw = vim.api.nvim_buf_get_lines(quiet, 0, -1, false)
ai._calendar_autodetect(quiet, raw, table.concat(raw, '\n'))
ai._start_calendar_analysis = analysis

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, replaced)
ai._check_agenda_duplicates = function(_, _, done) if done then done(true) end end
local tick = vim.api.nvim_buf_get_changedtick(buf)
ai._apply_articlemeta_calendar_result(buf, { code = 0, stdout = [[---
calendar:
  calendar_ready: true
  event_candidate: true
  calendar_title: Concert
  event_date: '2027-11-05'
  start_time: '20:30'
  location_name: Hedon
  city: Zwolle
  calendar_body: De band speelt.
---
]] }, tick)
text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('## Kalender', 1, true) < text:find('## Niet voor publicatie', 1, true),
  'agenda-aanhechting verplaatste het naslagblok niet naar onderaan')

-- Vrije AI-herschrijving krijgt alleen body en bewaart het bronblok.
local original_system, original_post = vim.system, ai._post_full_article_rewrite
local completed = false
ai._post_full_article_rewrite = function() completed = true end
vim.system = function(_, opts, callback)
  assert(not opts.stdin:find('Lennartz', 1, true) and not opts.stdin:find('€38,50', 1, true),
    'privé-bronnotities gingen naar AI')
  callback { code = 0, stdout = 'Nieuwe kop\n\nZWOLLE - Nieuwe tekst.', stderr = '' }
  return { kill = function() end }
end
-- De bestaande vrije promptflow zet *** onder het gehele document.
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '***', 'Herschrijf de tekst.' })
ai.ai_prompt_rewrite()
assert(vim.wait(1000, function() return completed end, 20))
text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('Nieuwe kop', 1, true) and text:find('> Entree: €38,50', 1, true),
  'AI-herschrijving verloor de bronnotities')
vim.system, ai._post_full_article_rewrite = original_system, original_post
print('editorial notes: OK')
