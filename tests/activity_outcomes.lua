-- Alleen gevalideerde, actuele uitkomsten worden als succes gepresenteerd.
local activity = require 'article_activity'
local duplicates = require 'pubble_duplicates'
local ai = require 'ai_text'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local source = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Mijn artikel.' })
vim.api.nvim_set_current_buf(source)
local native_system, native_show = vim.system, duplicates.show
local launches, reply = 0, nil
vim.system = function(_, _, done)
  launches = launches + 1
  reply = done
  return { kill = function() end }
end
local function messages()
  local entries = activity.snapshot(source).entries
  local result = {}
  for _, entry in ipairs(entries) do
    result[#result + 1] = entry.message
  end
  return table.concat(result, '\n')
end
local function run(payload, options, code)
  local finished, value = false, nil
  duplicates.check({ 'gemockte-doublurecontrole' }, function(approved)
    finished, value = true, approved
  end, vim.tbl_extend('force', { buf = source }, options or {}))
  assert(next(activity.snapshot(source).tasks), 'doublurecontrole is niet zichtbaar tijdens uitvoeren')
  reply { code = code or 0, stdout = vim.json.encode(payload), stderr = code and 'Bewuste fout' or '' }
  assert(vim.wait(1000, function() return finished end), 'controle bleef hangen')
  assert(next(activity.snapshot(source).tasks) == nil, 'afgelopen controle bleef als lopend staan')
  return value
end
assert(run { version = 1, performed = true, history_complete = true, candidates = {} })
assert(messages():find('Doublurecontrole afgerond: geen mogelijke doublures gevonden.', 1, true), 'negatieve controle bleef stil')
local first = #activity.snapshot(source).entries
assert(run { version = 1, performed = false, history_complete = false, candidates = {} })
local skipped = activity.snapshot(source).entries
assert(skipped[#skipped].message:find('overgeslagen', 1, true), 'overgeslagen controle kreeg geen eerlijke melding')
for index = first + 1, #skipped do
  assert(not skipped[index].message:find('geen mogelijke doublures', 1, true), 'overslaan werd als geslaagde controle gemeld')
end
assert(run { version = 1, performed = true, history_complete = false, candidates = {} })
local incomplete = activity.snapshot(source).entries
assert(
  incomplete[#incomplete].level == vim.log.levels.WARN and incomplete[#incomplete].message:find('onvolledig', 1, true),
  'onvolledige controle werd als niets gevonden gemeld'
)
local select = vim.ui.select
vim.ui.select = function(_, _, done) done 'Annuleren' end
assert(run({}, nil, 1) == false, 'mislukte controle blokkeerde niet op de bestaande keuze')
vim.ui.select = select
first = #activity.snapshot(source).entries
assert(run({ version = 1, performed = true, history_complete = true, candidates = {} }, { is_current = function() return false end }) == false)
local stale = activity.snapshot(source).entries
for index = first + 1, #stale do
  assert(not stale[index].message:find('geen mogelijke doublures', 1, true), 'verouderde controle werd als geslaagd gemeld')
end

duplicates.show = function(_, done) done(false) end
assert(run { version = 1, performed = true, history_complete = true, candidates = { { headline = 'Andere kop' } } } == false)
assert(messages():find('1 mogelijke doublure', 1, true), 'gevonden kandidaat ontbreekt in logboek')
assert(activity.snapshot(source).entries[#activity.snapshot(source).entries].kind ~= 'success', 'kandidaat kreeg onterecht OK')
assert(not activity.snapshot(source).issues['Pubble · Doublurecontrole'], 'uitgevoerde controle liet oude uitvoeringsfout staan')

local agenda = ai._agenda_duplicate_candidates
ai._agenda_duplicate_candidates = function(_, _, done) done { version = 1, performed = true, candidates = {}, errors = {} } end
ai._check_agenda_duplicates(source, { 'B' }, function() end)
assert(messages():find('Agenda-doublurecontrole afgerond: geen mogelijke doublures gevonden.', 1, true), 'agendacontrole zonder treffers bleef stil')
ai._agenda_duplicate_candidates = agenda

local count = #activity.snapshot(source).entries
assert(not ai._notify_web_publication_result(source, { mode = 'planned', phases = { { name = 'web', status = 'succeeded' } } }))
assert(not ai._notify_web_publication_result(source, { mode = 'published', phases = { { name = 'web', status = 'failed' } } }))
assert(
  not ai._notify_web_publication_result(
    source,
    { mode = 'failed', phases = { { name = 'web', status = 'succeeded', messages = { 'Online gepubliceerd volgens Pubble.' } } } }
  )
)
assert(#activity.snapshot(source).entries == count, 'plan of webfout werd als geplaatste website gemeld')
assert(ai._notify_web_publication_result(source, {
  mode = 'published',
  outcome = 'partial',
  phases = {
    {
      name = 'web',
      status = 'succeeded',
      messages = { '[B] Concept opgeslagen in Pubble (niet online).', '[SW] Ingepland voor 20-10-2026 13:00 in Pubble.' },
    },
    { name = 'teams', status = 'failed' },
  },
}))
assert(messages():find('[B] Concept opgeslagen', 1, true) and messages():find('[SW] Ingepland voor', 1, true), 'kernuitkomsten ontbreken')
assert(ai._notify_web_publication_result(source, { mode = 'published', phases = { { name = 'web', status = 'succeeded' } } }))
assert(messages():find('controleer conceptstatus en planning', 1, true), 'oud kerncontract werd niet veilig afgehandeld')
assert(launches == 6, 'presentatie voegde controles/subprocessen toe')

-- Ook een ongewijzigd taalresultaat wordt bevestigd. Een late reactie mag
-- geen succes tonen en geen nieuwere tekst overschrijven.
ai.tekstcheck()
reply { code = 0, stdout = 'Kop\n\nMijn artikel.' }
assert(vim.wait(1000, function() return (vim.b[source].pending_jobs or 0) == 0 end), 'tekstcheck bleef hangen')
assert(messages():find('Tekstcheck afgerond: geen correcties of suggesties.', 1, true), 'ongewijzigde tekstcheck bleef stil')
count = #activity.snapshot(source).entries
ai.tekstcheck()
vim.api.nvim_buf_set_lines(source, -1, -1, false, { 'Nieuwere tekst.' })
reply { code = 0, stdout = 'Verouderd resultaat' }
assert(vim.wait(1000, function() return (vim.b[source].pending_jobs or 0) == 0 end), 'late tekstcheck bleef hangen')
assert(vim.api.nvim_buf_get_lines(source, -2, -1, false)[1] == 'Nieuwere tekst.', 'late tekstcheck overschreef nieuwere bewerking')
local late_entries = activity.snapshot(source).entries
for index = count + 1, #late_entries do
  assert(late_entries[index].kind ~= 'success', 'verworpen tekstcheck kreeg succesmelding')
end
assert(launches == 8, 'succesmeldingen voegden extra checks toe')
vim.system, duplicates.show = native_system, native_show
print 'activity outcomes: OK'
