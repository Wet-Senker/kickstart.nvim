local ai = require('ai_text')
local recognition = require('article_recognition')
local krant = require('krant')
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
krant.config.desktop = tmp
ai._duplicate_stage_runner = function(_, done) done(true, { performed = false, candidates = {} }) end
local runner = ai._column_recognition_runner
local candidate = {
  id = 'natuurvereniging', label = 'Column Natuurvereniging IJsseldelta',
  confidence = 100, points = 100, policy = 'confirm', category = 'rubric',
  evidence = { 'auteursregel: Suzanne Beurmanjer' }, state = 'candidate',
  suppress_calendar = true,
}
local decision = recognition.rubric_decision(recognition.evaluate('', { candidate }))
assert(decision.action == 'confirm', 'natuurcolumn mag ook bij score 100 nooit automatisch')

local function article()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', 'Groene trends en educatie', '',
    'De columntekst blijft letterlijk behouden.', '',
    'De lezing begint om 13.30 uur. Gratis toegang; iedereen kan deelnemen.', '',
    'Mail naar educatiewerkgroep\\@natuurverenigingijsseldelta.nl.',
    'Suzanne Beurmanjer natuurverenigingijsseldelta.nl',
  })
  return buf
end
local function content(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function await(test) assert(vim.wait(5000, test, 10), 'columnherkenning niet afgerond') end
local calls = 0
ai._column_recognition_runner = function(buf, body, done)
  calls = calls + 1
  assert(not body:find('=== ARTIKEL ===', 1, true), 'core kreeg controleregels')
  runner(buf, body, done)
end
local asks = 0
ai._rubric_confirm = function(d)
  asks = asks + 1
  assert(d.candidate.id == 'natuurvereniging')
  return d.candidate
end
local accepted = article()
local calendar_calls = 0
ai._start_calendar_analysis = function() calendar_calls = calendar_calls + 1 end
ai._article_autodetect(accepted)
await(function() return vim.b[accepted].recognized_rubric == 'natuurvereniging' end)
assert(asks == 1 and calls == 1, 'bevestiging of Python-call niet exact eenmaal')
assert(calendar_calls == 0, 'bevestigde column startte onnodig kalender-AI')
assert(content(accepted):find('Column Natuurvereniging: Groene trends en educatie', 1, true))
assert(content(accepted):find('De columntekst blijft letterlijk behouden.', 1, true))
assert(content(accepted):find('rubriek: column', 1, true))
assert(content(accepted):find('Suzanne Beurmanjer', 1, true))

-- Een opnieuw geopende vaste vorm wordt herkend zonder nieuwe vraag/template.
local before = content(accepted)
local reopened = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(reopened, 0, -1, false, vim.split(before, '\n'))
ai._article_autodetect(reopened)
await(function() return vim.b[reopened].recognized_rubric == 'natuurvereniging' end)
assert(content(reopened) == before and asks == 1, 'heropening paste template opnieuw toe')
assert(calendar_calls == 0, 'bestaande column startte onnodig kalender-AI')

-- Afwijzen/annuleren past niets toe, ook bij een herhaalde importcallback.
ai._rubric_confirm = function() asks = asks + 1; return nil end
local rejected = article()
before = content(rejected)
ai._article_autodetect(rejected)
await(function() return asks == 2 end)
assert(content(rejected) == before, 'afwijzing wijzigde artikel')
ai._article_autodetect(rejected)
assert(asks == 2, 'afwijzing werd genegeerd')

-- Een late core-uitkomst mag nieuwere tekst niet overschrijven of een menu openen.
local pending
ai._column_recognition_runner = function(_, _, done) pending = done end
local stale = article()
ai._article_autodetect(stale)
await(function() return pending ~= nil end)
vim.api.nvim_buf_set_lines(stale, -1, -1, false, { 'Nieuwe eigen tekst.' })
before = content(stale)
pending({ candidate })
assert(content(stale) == before and asks == 2, 'late herkenning overschreef nieuwere tekst')

-- Ook tijdens de bevestigingsdialoog blijft een nieuwere bewerking leidend.
ai._column_recognition_runner = function(_, _, done) done({ candidate }) end
local edited = article()
ai._rubric_confirm = function(d)
  vim.api.nvim_buf_set_lines(edited, -1, -1, false, { 'Tijdens keuze gewijzigd.' })
  return d.candidate
end
ai._article_autodetect(edited)
await(function() return content(edited):find('Tijdens keuze gewijzigd.', 1, true) ~= nil end)
assert(not content(edited):find('Column Natuurvereniging:', 1, true), 'keuze overschreef nieuwere tekst')

-- Een oudere/kapotte core mag de resterende importflow niet laten hangen.
local original_system = vim.system
local fallback
vim.system = function(_, _, done)
  done({ code = 1, stdout = '', stderr = 'module ontbreekt' })
end
runner(edited, 'Tekst', function(items) fallback = items end)
await(function() return fallback ~= nil end)
assert(#fallback == 0, 'corefout leverde toch kandidaten op')
fallback = nil
vim.system = function() error('python ontbreekt') end
runner(edited, 'Tekst', function(items) fallback = items end)
assert(fallback and #fallback == 0, 'startfout liet de importflow hangen')
vim.system = original_system

vim.fn.delete(tmp, 'rf')
print('nature recognition: OK')
