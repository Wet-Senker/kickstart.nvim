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
  assert(value:find('Jouw huidige bericht:', 1, true))
  assert(value:find('Control + c  Later beoordelen', 1, true))
  assert(not value:find('Ctrl-c', 1, true) and not value:find('automatische agenda wacht', 1, true))
  if case[1]:find('12.39', 1, true) then assert(value:find('12.39 uur (gisteren)', 1, true)) end
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
print 'duplicate selection labels: OK'
