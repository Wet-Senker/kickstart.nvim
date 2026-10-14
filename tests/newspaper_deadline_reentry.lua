local ai = require 'ai_text'

local planning = { display_dates = { B = '2026-10-15' }, editions = { 'B', 'SW', 'D' } }
local status = {
  mode = 'needs_newspaper_deadline',
  phases = {},
  newspaper_deadline_review = {
    signature = 'album-2026-10-16', late_editions = { 'B' },
    items = { { edition = 'B', name = 'De Brug', too_late = true } },
  },
}
local source = {
  'e: B, SW, D', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Artikel.',
  '', '## Kranttijdsversies', '', 'Bestaande beoordeelde krantvariant.',
}
local function fresh()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
  vim.b[buf].skip_newspaper_editions = { 'D' }
  return buf
end
local function resume(buf, choice, before_choice)
  local questions = 0
  ai._late_newspaper_confirm = function(review, done)
    questions = questions + 1
    assert(vim.deep_equal(review.late_editions, { 'B' }), 'andere krant kwam in de vraag')
    if before_choice then before_choice(buf) end
    done(choice)
  end
  local ready
  ai._resume_newspaper_deadline_review(buf, status, planning, function(value) ready = value end)
  assert(questions == 1, 'deadlinevraag ontbreekt of is dubbel gesteld')
  return ready
end

local buf = fresh()
assert(resume(buf, 2), 'expliciete krantkeuze hervatte niet')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source), 'krantvariant gewijzigd')
local state = vim.b[buf].publication_review_state
assert(vim.deep_equal(state.display_dates, planning.display_dates), 'webplanning ging verloren')
assert(vim.deep_equal(state.editions, planning.editions), 'bestemmingen gingen verloren')
assert(state.late_newspaper_decision.mode == 'force', 'toestemming ontbreekt bij herstart')
assert(vim.deep_equal(state.late_newspaper_decision.editions, { 'B' }), 'andere krant kreeg toestemming')
assert(vim.deep_equal(state.skip_newspaper_editions, { 'D' }), 'bestaande web-onlykeuze ging verloren')

buf = fresh()
vim.b[buf].late_newspaper_decision = { mode = 'force', editions = { 'SW' }, signature = 'oude-keuze' }
assert(resume(buf, 2), 'nieuwe krantkeuze hervatte niet')
state = vim.b[buf].publication_review_state
assert(vim.deep_equal(state.late_newspaper_decision.editions, { 'SW', 'B' }), 'eerdere kranttoestemming vervangen')

buf = fresh()
vim.b[buf].late_newspaper_decision = { mode = 'force', editions = { 'SW' }, signature = 'oude-keuze' }
assert(resume(buf, 1), 'gemengde websitekeuze hervatte niet')
state = vim.b[buf].publication_review_state
assert(vim.deep_equal(state.late_newspaper_decision.editions, { 'SW' }), 'eerdere toestemming voor SW verloren')
assert(vim.deep_equal(state.skip_newspaper_editions, { 'D', 'B' }), 'websitekeuze voor B verloren')

buf = fresh()
assert(resume(buf, 1), 'websitekeuze hervatte niet')
state = vim.b[buf].publication_review_state
assert(state.late_newspaper_decision.mode == 'website', 'websitekeuze verloren')
assert(vim.deep_equal(state.skip_newspaper_editions, { 'D', 'B' }), 'web-onlykeuze sloot andere krant uit')
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('krantuitzondering: B', 1, true), 'websitekeuze niet zichtbaar vastgelegd')
assert(text:find('Bestaande beoordeelde krantvariant.', 1, true), 'krantvariant ging verloren')

buf = fresh()
assert(not resume(buf, 3), 'annuleren hervatte')
assert(vim.b[buf].publication_review_state == nil, 'annuleren legde akkoord vast')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), source), 'annuleren wijzigde tekst')

buf = fresh()
assert(not resume(buf, 2, function(target)
  vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuwe gebruikersbewerking.' })
end), 'gewijzigde bron kreeg akkoord')
assert(vim.b[buf].late_newspaper_decision == nil, 'late callback legde akkoord vast')

local rejected
ai._resume_newspaper_deadline_review(fresh(), {}, planning, function(value) rejected = value end)
assert(rejected == false, 'ontbrekend beslisplan werd geaccepteerd')
local parsed = ai._publication_status_from_output(
  'PUBBLE_RESULT_JSON: ' .. vim.json.encode(status), ''
)
assert(parsed.mode == 'needs_newspaper_deadline', 'nieuwe modus niet herkend')
assert(parsed.newspaper_deadline_review.signature == 'album-2026-10-16', 'beslisplan verloren')

-- Dezelfde aankondiging was al expliciet voor de latere krant herschreven:
-- geen tweede deadlinevraag en geen bredere, ongebonden force-toestemming.
buf = fresh()
ai._late_newspaper_confirm = function() error('dubbele deadlinevraag na kranttijdkeuze') end
local matched = vim.deepcopy(status.newspaper_deadline_review)
matched.timing_deadline_approved_editions = { 'B' }
local ready
ai._review_late_newspapers(buf, matched, function(value) ready = value end)
assert(ready == true, 'bestaande kranttijdkeuze blokkeerde verzending')
assert(vim.b[buf].late_newspaper_decision == nil, 'datumgebonden toestemming werd algemene force')

matched.late_editions = { 'B', 'SW' }
local asked_for
ai._late_newspaper_confirm = function(review, done)
  asked_for = review.late_editions
  done(3)
end
ai._review_late_newspapers(buf, matched, function(value) ready = value end)
assert(vim.deep_equal(asked_for, { 'SW' }), 'toestemming voor B werd naar andere krant uitgebreid')
assert(ready == false, 'annuleren van onafhankelijke deadline hervatte')

print 'newspaper deadline reentry: OK'
