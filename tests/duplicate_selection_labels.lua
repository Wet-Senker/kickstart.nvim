local ui = require 'duplicate_selection_ui'
local function key(buf, name)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.lhs:lower() == name:lower() then map.callback(); return end
  end
  error('Toets ontbreekt: ' .. name)
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

local cases = {
  { '2026-10-25', '2026-10-25', '(vandaag)' },
  { '24-10-2026 om 12.39 uur', '2026-10-25', '(gisteren)' },
  { '2026-10-26', '2026-10-25', '(morgen)' },
  { '2026-10-23', '2026-10-25', '(2 dagen geleden)' },
  { '2026-10-27', '2026-10-25', '(over 2 dagen)' },
  { '2026-03-28', '2026-03-29', '(gisteren)' },
  { '2026-03-30', '2026-03-29', '(morgen)' },
  { '2026-12-31', '2027-01-01', '(gisteren)' },
  { '2028-02-29', '2028-03-01', '(gisteren)' },
}
for _, case in ipairs(cases) do
  local closed
  ui.show({ candidates = { { comparison = { date = case[1], headline = 'Huidige tekst' },
    variants = { { publication = 'De Brug', headline = 'Bestaande tekst',
      display_date_short = case[1], created_date_short = case[1],
      created_by = '12258', created_by_label = 'Ingezonden', text = 'Artikeltekst.',
      review_selectable = true, review_target = { id = 'pair' } } } } } },
    function(ok) closed = ok end, { today = case[2] })
  local buf = vim.api.nvim_get_current_buf()
  local value = text(buf)
  assert(not value:find('Vergelijk het bestaande bericht', 1, true))
  assert(not value:find('12258', 1, true) and value:find('Ingezonden', 1, true))
  assert(value:find(case[3], 1, true), 'Relatieve datum ontbreekt: ' .. value)
  assert(value:find('Jouw bericht:', 1, true))
  assert(value:find('q  Keuzes bewaren en sluiten', 1, true))
  assert(not value:find('Control+c', 1, true), 'annulering bleef onnodig in het overzicht staan')
  assert(not value:find('Onbeoordeeld is geen besluit', 1, true))
  assert(not value:find('Ctrl-c', 1, true) and not value:find('automatische agenda wacht', 1, true))
  if case[1]:find('12.39', 1, true) then assert(value:find('24-10-2026, 12.39 (gisteren)', 1, true)) end
  key(buf, '<CR>')
  value = text(buf)
  assert(value:find(case[3], 1, true) and value:find('Ingezonden', 1, true))
  assert(not value:find('12258', 1, true))
  key(buf, '<C-c>')
  assert(closed == false, 'Control+c wijzigde de bestaande uitstelbetekenis')
end

-- JSON-null of een ongeldige datum mag geen fout of verzonnen dag geven.
local report = vim.json.decode([[{"candidates":[{"variants":[{"publication":"De Brug",
  "headline":"Zonder gegevens","display_date_short":null,"display_date_label":"31-02-2026",
  "created_by":null,"created_by_label":null}]}]}]])
ui.show(report, function() end, { today = '2026-10-25' })
local buf = vim.api.nvim_get_current_buf()
assert(text(buf):find('31-02-2026', 1, true) and not text(buf):find('NIL', 1, true))
key(buf, '<C-c>')

-- Korte kanaalnamen delen dezelfde datumkolom; de popup past bij zijn inhoud.
local mixed = { candidates = { { variants = {
  { publication = 'De Brug', kind = 'web', headline = 'Webbericht',
    display_date_short = '25-10-2026 om 18.06 uur', review_selectable = true, review_target = { id = 'web' } },
  { publication = 'De Brug', kind = 'agenda', headline = 'Agendabericht',
    display_date_short = '25-10-2026 om 19.30 uur', review_selectable = true, review_target = { id = 'agenda' } },
} } } }
vim.o.columns, vim.o.lines = 180, 50
local applied, closed = {}, nil
local function apply(_, choices, done)
  applied[#applied + 1] = vim.deepcopy(choices)
  done(true)
end
ui.show(mixed, function(ok) closed = ok end, { today = '2026-10-26', on_apply = apply })
buf = vim.api.nvim_get_current_buf()
local dates = {}
for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if line:find('Web:', 1, true) or line:find('Agenda:', 1, true) then
    dates[#dates + 1] = line:find('25-10-2026, ', 1, true)
    if line:find('Web:', 1, true) then vim.api.nvim_win_set_cursor(0, { row, 0 }) end
  end
end
assert(#dates == 2 and dates[1] == dates[2], 'datumkolommen niet uitgelijnd')
assert(vim.api.nvim_win_get_height(0) < 12, 'klein overzicht hield een onnodig groot venster')
key(buf, 'm'); key(buf, '<C-c>')
assert(closed == false and #applied == 0, 'Control+c bewaarde nieuwe keuzes')
ui.show(mixed, function(ok) closed = ok end, { today = '2026-10-26', on_apply = apply })
buf = vim.api.nvim_get_current_buf()
key(buf, 'm'); key(buf, 'q')
assert(closed == true and #applied == 1 and next(applied[1]), 'q bewaarde de markering niet')

local saved = { saved_selections = { { id = 'saved', kind = 'web', edition = 'B', headline = 'Eerdere keuze', existing = {} } } }
local original = vim.deepcopy(saved)
ui.show(saved, function() end, { on_apply = apply })
buf = vim.api.nvim_get_current_buf()
key(buf, 'm'); key(buf, '<C-c>')
assert(vim.deep_equal(saved, original) and #applied == 1, 'Control+c wiste eerder bewaarde keuzes')

-- Multiple hits share one decision, but same-day events and other editions do not.
local function candidate(kind, edition, id, event)
  return { kind = kind, source_event = event,
    comparison = event and { date = event.date, headline = event.ref } or nil,
    variants = { { kind = kind, edition = edition, headline = id, text = 'Tekst van ' .. id,
      editor_url = 'https://example.invalid/' .. id, review_selectable = true,
      review_target = { id = id, kind = kind, edition = edition, source_event = event } } } }
end
local function row(fragment)
  for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(fragment, 1, true) then
      vim.api.nvim_win_set_cursor(0, { index, 0 })
      return line, index
    end
  end
  error('Regel ontbreekt: ' .. fragment)
end
local first = { ref = 'Eerste afspraak', date = '2026-10-25', structured = true }
local second = { ref = 'Tweede afspraak', date = first.date, structured = true }
local browser = require 'ordered_browser'
local original_open = browser.open_urls
local opened
browser.open_urls = function(urls) opened = urls end
ui.show({ candidates = {
  candidate('web', 'B', 'Brug één'), candidate('web', 'B', 'Brug twee'),
  candidate('web', 'SW', 'Zwolle web'),
  candidate('agenda', 'B', 'Agenda één', first), candidate('agenda', 'B', 'Agenda twee', first),
  candidate('agenda', 'B', 'Andere afspraak', second), candidate('agenda', 'SW', 'Zwolle agenda', first),
} }, function() end, { on_apply = apply })
buf = vim.api.nvim_get_current_buf()
assert(text(buf):find('Brug één', 1, true) and text(buf):find('Agenda één', 1, true),
  'trefferkoppen stonden bij openen niet direct in beeld')
local group_line, group_row = row('Web:    2 treffers')
assert(group_line:find('[−]', 1, true) and group_line:find('[geen doublures]', 1, true),
  'open groep of gezamenlijke geen-doublureactie ontbreekt')
local original_getmousepos = vim.fn.getmousepos
vim.fn.getmousepos = function() return {
  winid = vim.api.nvim_get_current_win(), line = group_row,
  column = assert(group_line:find('[geen doublures]', 1, true)),
} end
key(buf, '<LeftMouse>')
assert(row('Web:    2 treffers'):find('[≠]', 1, true), 'één klik markeerde de groep niet als geen doublures')
group_line, group_row = row('Web:    2 treffers')
vim.fn.getmousepos = function() return {
  winid = vim.api.nvim_get_current_win(), line = group_row,
  column = assert(group_line:find('[keuze wissen]', 1, true)),
} end
key(buf, '<LeftMouse>')
vim.fn.getmousepos = original_getmousepos
assert(row('Web:    2 treffers'):find('[ ]', 1, true), 'tweede klik wiste de groepskeuze niet')
row('Web:    2 treffers'); key(buf, 'm')
assert(row('Web:    2 treffers'):find('[ ]', 1, true), 'een treffer werd zonder keuze bevestigd')
row('Brug twee'); key(buf, '<CR>')
assert(text(buf):find('Tekst van Brug twee', 1, true))
key(buf, 'o')
assert(vim.deep_equal(opened, { 'https://example.invalid/Brug twee' }))
key(buf, '<CR>')
key(buf, 'm')
assert(row('Web:    2 treffers'):find('[=]', 1, true))
opened = nil
key(buf, 'o')
assert(vim.deep_equal(opened, { 'https://example.invalid/Brug twee' }))
row('Eerste afspraak'); key(buf, 'n')
assert(row('Eerste afspraak'):find('[≠]', 1, true))
assert(row('Andere afspraak'):find('[ ]', 1, true) and row('Zwolle agenda'):find('[ ]', 1, true))
key(buf, 'q')
assert(vim.deep_equal(applied[2], {
  ['Brug twee'] = 'duplicate', ['Agenda één'] = 'different', ['Agenda twee'] = 'different',
}), 'groepskeuze raakte een ander evenement, andere krant of onbevestigde webtreffer')
browser.open_urls = original_open
print 'duplicate selection labels: OK'
