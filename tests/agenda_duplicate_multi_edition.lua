-- Echt Lua → Python-contract, zonder evenementdatum of externe leescalls.
local ai = require 'ai_text'
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local buf = vim.api.nvim_create_buf(true, false)
local lines = {
  'e: B, SW, ST, K', '', '=== ARTIKEL ===', '', 'Vuurwerkcampagne', '',
  'OVERIJSSEL - Meld verdachte vuurwerkopslag bij Meld Misdaad Anoniem.',
}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.api.nvim_set_current_buf(buf)
local native_system = vim.system
local launches = {}
vim.system = function(command, options, callback)
  launches[#launches + 1] = vim.deepcopy(command)
  return native_system(command, options, callback)
end

local function check(codes)
  local finished = false
  ai._check_agenda_duplicates(buf, codes, function(approved)
    assert(approved == true, 'De controle mag de gewone artikelroute niet blokkeren')
    finished = true
  end)
  assert(vim.wait(10000, function() return finished end), 'Agendacontrole bleef hangen')
  assert(next(activity.snapshot(buf).tasks) == nil, 'Afgeronde controle bleef actief')
  assert(vim.deep_equal(require('article_notices').content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
    require('article_notices').content_lines(lines)),
    'De controle wijzigde het artikel')
end

check { 'B', 'SW', 'ST', 'K' }
assert(#launches == 1, 'Meerdere edities mogen geen extra subprocessen starten')
assert(launches[1][#launches[1]] == 'B,SW,ST,K', 'Gekozen edities gingen verloren')
local entries = activity.snapshot(buf).entries
assert(entries[#entries].message:find('geen vergelijking nodig', 1, true),
  'Artikel zonder datum werd niet netjes overgeslagen')
for _, entry in ipairs(entries) do
  assert(entry.level < vim.log.levels.WARN, 'Geldige edities veroorzaakten een waarschuwing')
end

-- Een echte invoerfout blijft zichtbaar; we verbergen de foutmelding niet.
check { 'B', 'XX' }
entries = activity.snapshot(buf).entries
assert(entries[#entries].level == vim.log.levels.WARN
  and entries[#entries].message:find('controle mislukt', 1, true),
  'Een echte fout werd stil verborgen')
assert(#launches == 2, 'De foutafhandeling startte onverwachte herpogingen')
vim.system = native_system
print 'agenda duplicate multi edition: OK'
