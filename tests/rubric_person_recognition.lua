local ai = require('ai_text')
local krant = require('krant')
local layout_export = require('layout_export')

local tmp = vim.fn.tempname()
local photo_root = tmp .. '/photos'
local inbox = tmp .. '/inbox'
local desktop = tmp .. '/Desktop'
vim.fn.mkdir(photo_root .. '/raadspraat/CDA', 'p')
vim.fn.mkdir(photo_root .. '/raadspraat/Hart voor Kampen', 'p')
vim.fn.mkdir(photo_root .. '/ondernemen_in_kampen', 'p')
vim.fn.mkdir(inbox, 'p')
vim.fn.mkdir(desktop, 'p')
vim.fn.writefile({ 'foto' }, photo_root .. '/raadspraat/CDA/Niek Teune.png')
vim.fn.writefile({ 'foto' }, photo_root .. '/raadspraat/Hart voor Kampen/Nardus Koster.png')
vim.fn.writefile({ 'foto' }, photo_root .. '/ondernemen_in_kampen/Jan Groen.jpg')
vim.fn.writefile({ 'foto' }, photo_root .. '/ondernemen_in_kampen/Nardus Koster.jpg')
vim.fn.writefile({
  'naam: Jan Groen',
  'functie: testondernemer.',
  '',
  'naam: Nardus Koster',
  'functie: binnenstadsondernemer.',
}, photo_root .. '/ondernemen_in_kampen/personen.md')

vim.env.TEXTTOOLS_INBOX_DIR = inbox
krant.config.photo_root = photo_root
krant.config.desktop = desktop

local original_runner = ai._column_recognition_runner
local original_duplicate_runner = ai._duplicate_stage_runner
local original_confirm = ai._rubric_confirm
local original_select = vim.ui.select
ai._duplicate_stage_runner = function(_, callback)
  callback(true, { performed = false, candidates = {} })
end
vim.ui.select = function() error('vooraf geselecteerde persoon opende onverwacht een submenu') end

local function candidate(rubric, name, photo, party)
  local is_council = rubric == 'raadspraat'
  local rubric_label = is_council and 'Raadspraat' or 'Ondernemen in Kampen'
  local relative = is_council and ('raadspraat/' .. party .. '/' .. photo)
    or ('ondernemen_in_kampen/' .. photo)
  local label = rubric_label .. ' — ' .. name
  if party then label = label .. ' (' .. party .. ')' end
  return {
    id = is_council and 'raadspraat' or 'ondernemen',
    label = label,
    photo = photo_root .. '/' .. relative,
    confidence = 100,
    points = 100,
    category = 'rubric',
    policy = 'confirm',
    state = 'candidate',
    suppress_calendar = true,
    explicit = false,
  }
end

local function article(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B',
    '',
    '=== ARTIKEL ===',
    '',
    'Een aangeleverde kop',
    '',
    'De volledige bijdrage.',
    '',
    name,
  })
  return buf
end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local function clear_inbox()
  vim.fn.delete(inbox, 'rf')
  vim.fn.mkdir(inbox, 'p')
end

local function wait_for(predicate, message)
  assert(vim.wait(5000, predicate, 20), message)
end

-- Eén volledige naam geeft één bevestiging en gebruikt daarna rechtstreeks de
-- gevonden foto in dezelfde Ondernemen-flow, zonder een tweede personenmenu.
local jan = candidate('ondernemen', 'Jan Groen', 'Jan Groen.jpg')
ai._column_recognition_runner = function(_, _, callback) callback({ jan }) end
local decision_seen
ai._rubric_confirm = function(decision)
  decision_seen = decision
  return decision.candidates[1]
end
local jan_buf = article('Jan Groen')
local sentinel = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(sentinel, 0, -1, false, { 'niet wijzigen' })
vim.api.nvim_set_current_buf(sentinel)
ai._article_autodetect(jan_buf)
wait_for(function() return vim.b[jan_buf].recognized_rubric == 'ondernemen' end, 'Ondernemen-herkenning werd niet afgerond')

local jan_text = text(jan_buf)
assert(decision_seen and #decision_seen.candidates == 1, 'unieke naam gaf geen gerichte bevestiging')
assert(jan_text:find('z - 1 Ondernemen in Kampen Jan Groen', 1, true), 'Ondernemen-werktitel ontbreekt')
assert(jan_text:find('Column Ondernemen in Kampen: Een aangeleverde kop', 1, true), 'Ondernemen-template ontbreekt')
assert(layout_export.pending(jan_buf), 'Ondernemen-exportplan ontbreekt')
assert(vim.fn.filereadable(inbox .. '/Jan Groen.jpg') == 1, 'gevonden persoonsfoto is niet voorbereid')
assert(text(sentinel) == 'niet wijzigen', 'persoonsherkenning wijzigde de actieve verkeerde buffer')

-- Nee wordt voor deze buffersessie onthouden en laat tekst, foto en exportplan
-- volledig ongemoeid.
clear_inbox()
local rejected = article('Jan Groen')
local before_reject = text(rejected)
local confirm_count = 0
ai._rubric_confirm = function()
  confirm_count = confirm_count + 1
  return nil
end
ai._article_autodetect(rejected)
wait_for(function() return confirm_count == 1 end, 'persoonsbevestiging werd niet geopend')
ai._article_autodetect(rejected)
assert(confirm_count == 1, 'afgewezen persoonsherkenning vroeg opnieuw')
assert(text(rejected) == before_reject, 'afwijzing wijzigde de artikeltekst')
assert(not layout_export.pending(rejected), 'afwijzing maakte toch een exportplan')
assert(#vim.fn.glob(inbox .. '/*', false, true) == 0, 'afwijzing kopieerde toch een foto')

-- Nardus Koster komt in beide fotomappen voor. De keuze bepaalt expliciet
-- welke gespecialiseerde flow draait.
clear_inbox()
local nardus_raad = candidate(
  'raadspraat', 'Nardus Koster', 'Nardus Koster.png', 'Hart voor Kampen'
)
local nardus_ondernemen = candidate(
  'ondernemen', 'Nardus Koster', 'Nardus Koster.jpg'
)
ai._column_recognition_runner = function(_, _, callback)
  callback({ nardus_raad, nardus_ondernemen })
end
local nardus_candidates
ai._rubric_confirm = function(decision)
  nardus_candidates = decision.candidates
  for _, item in ipairs(decision.candidates) do
    if item.id == 'ondernemen' then return item end
  end
  return nil
end
local nardus_buf = article('Nardus Koster')
ai._article_autodetect(nardus_buf)
wait_for(function() return vim.b[nardus_buf].recognized_rubric == 'ondernemen' end, 'gekozen Nardus-rol werd niet toegepast')
local nardus_text = text(nardus_buf)
assert(#nardus_candidates == 2, 'dubbele rol van Nardus kwam niet in één keuze')
local seen_roles = {}
for _, item in ipairs(nardus_candidates) do seen_roles[item.id] = true end
assert(seen_roles.raadspraat, 'Raadspraatkandidaat ontbreekt')
assert(seen_roles.ondernemen, 'Ondernemenkandidaat ontbreekt')
assert(nardus_text:find('z - 1 Ondernemen in Kampen Nardus Koster', 1, true), 'gekozen Nardus-rol is niet toegepast')
assert(not nardus_text:find('z - 1 Raadspraat', 1, true), 'niet-gekozen Nardus-rol is toegepast')
assert(vim.fn.filereadable(inbox .. '/Nardus Koster.jpg') == 1, 'verkeerde Nardus-foto voorbereid')

-- Een core-uitkomst voor een inmiddels gewijzigde buffer mag de oude
-- kandidaat niet meer toepassen.
clear_inbox()
local stale_buf = article('Jan Groen')
local delayed_callback
ai._column_recognition_runner = function(_, _, callback) delayed_callback = callback end
ai._rubric_confirm = function() error('verouderde persoonskandidaat opende een bevestiging') end
ai._article_autodetect(stale_buf)
wait_for(function() return delayed_callback ~= nil end, 'uitgestelde columnherkenning startte niet')
vim.api.nvim_buf_set_lines(stale_buf, -1, -1, false, { '', 'De tekst is intussen gewijzigd.' })
delayed_callback({ jan })
assert(not text(stale_buf):find('Column Ondernemen in Kampen:', 1, true), 'laat resultaat overschreef nieuwere tekst')
assert(not layout_export.pending(stale_buf), 'verouderd resultaat maakte een exportplan')
assert(vim.b[stale_buf].article_recognition_done == nil, 'gewijzigde tekst bleef ten onrechte als herkend gemarkeerd')

ai._column_recognition_runner = original_runner
ai._duplicate_stage_runner = original_duplicate_runner
ai._rubric_confirm = original_confirm
vim.ui.select = original_select
vim.fn.delete(tmp, 'rf')
print('rubric person recognition: OK')
