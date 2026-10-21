local duplicates = require 'pubble_duplicates'
require('editions')._set { { code = 'B', name = 'De Brug' } }
local headline = 'Samenzangavond met Urker tintje'
local source = { headline = headline, date = '2026-10-31' }
local result = { candidates = {
  { headline = headline, comparison = source, kind = 'agenda', variants = { {
    publication = 'B', headline = headline, kind = 'agenda', display_date_label = '2026-10-31',
    text = 'Samen zingen in de kerk.', location = 'Buitenkerk', city = 'Kampen', editor_url = 'agenda-link',
  } } },
  { headline = 'IJsselmuiden Samenzangavond', comparison = source, kind = 'web', variants = { {
    publication = 'B', headline = 'IJsselmuiden Samenzangavond', kind = 'web',
    display_date_short = '30-10-2026 om 10.00 uur', display_date_label = '30 oktober 2026',
    text = 'Een bestaande aankondiging.', editor_url = 'web-link',
  } } },
} }
local options = { title = 'Mogelijke doublures', comparison_heading = 'Nieuw agenda-item ter vergelijking',
  approve_label = 'toch een agenda-item maken',
  reject_label = 'Agenda overslaan voor dit hele artikel; web en krant gaan door' }
local lines, ranges = duplicates.report_lines(result, options)
local text = table.concat(lines, '\n')
assert(not text:find('Mogelijke doublures', 1, true), 'de venstertitel wordt in de inhoud herhaald')
assert(text:find('De Brug', 1, true) and not text:find('\nB\n', 1, true))
assert(not text:find('Nieuw:', 1, true) and not text:find('2026-10-', 1, true))
local _, count = text:gsub('Nieuw agenda%-item ter vergelijking', '')
assert(count == 1, 'het nieuwe bericht staat meermaals boven de treffers')
assert(text:find('Enter / dubbelklik  Bekijk de beschikbare tekst en details in NVIM', 1, true))
assert(text:find('dit neemt nog geen besluit', 1, true))
assert(text:find('Agenda overslaan voor dit hele artikel; web en krant gaan door', 1, true))
local left, right = lines[ranges[1].first], lines[ranges[2].first]
assert(left:find('Agenda', 1, true) and right:find('Web', 1, true))
assert(left:find('31-10-2026', 1, true) == right:find('30-10-2026', 1, true), 'datums zijn niet uitgelijnd')
assert(left:find(headline, 1, true) == right:find('IJsselmuiden', 1, true), 'koppen zijn niet uitgelijnd')
assert(duplicates._dialog_width(lines, 240) <= 110, 'het scherm wordt onnodig breed')
assert(duplicates._dialog_width(lines, 40) <= 36, 'het venster past niet op een smal scherm')

local function key(buf, name)
  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if mapping.lhs == name then mapping.callback(); return end
  end
  error('Ontbrekende toets: ' .. name)
end
local decisions, browser_calls = {}, {}
require('ordered_browser').open_urls = function(urls) browser_calls[#browser_calls + 1] = urls end
duplicates.show(result, function(choice) decisions[#decisions + 1] = choice end, options)
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_config(win).title[1][1]:find('Mogelijke doublures', 1, true))
key(buf, '<CR>')
text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('Soort: Agenda', 1, true) and text:find('Krant: De Brug', 1, true))
assert(text:find('Datum: 31-10-2026', 1, true))
assert(text:find('Samen zingen in de kerk.', 1, true) and text:find('Locatie: Buitenkerk', 1, true))
assert(#decisions == 0 and #browser_calls == 0, 'Enter nam een besluit of opende de browser')
key(buf, 'q')
-- Een dubbelklik opent eveneens alleen details en neemt geen besluit.
local original_mouse = vim.fn.getmousepos
vim.fn.getmousepos = function() return { winid = win, line = ranges[2].first, column = 1 } end
key(buf, '<2-LeftMouse>')
vim.fn.getmousepos = original_mouse
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Soort: Web', 1, true))
assert(#decisions == 0 and #browser_calls == 0)
key(buf, 'q')
key(buf, 'n')
assert(decisions[1] == 'reject', 'n moet uitsluitend de bestaande overslaankeuze doorgeven')

-- Ontbrekende body mag niet als volledige tekst of als leeg succes worden gepresenteerd.
duplicates.show({ candidates = { { headline = 'Zonder tekst', variants = { { publication = 'De Brug' } } } } }, function() end)
buf = vim.api.nvim_get_current_buf()
key(buf, '<CR>')
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Geen berichttekst meegeleverd', 1, true))
key(buf, 'q'); key(buf, 'q')

-- Meerdere nieuwe evenementen blijven afzonderlijk herkenbaar, niet samengevoegd.
local multiple = vim.deepcopy(result)
multiple.candidates[2].comparison = { headline = 'Tweede nieuw evenement', date = '2026-11-01' }
local multi_lines, multi_ranges = duplicates.report_lines(multiple, options)
assert(#multi_ranges == 2)
assert(table.concat(multi_lines, '\n'):find('Vergelijk met nieuw bericht 2', 1, true))
assert(duplicates._candidate_at_cursor(multi_ranges, multi_ranges[2].last) == multiple.candidates[2])

-- Additieve Python-velden kunnen JSON-null zijn; geen "vim.NIL" en correcte fallback.
local nulls = vim.json.decode([[{"candidates":[{"headline":"Onbekende datum","variants":[{
  "publication":"De Brug","headline":"Onbekende datum","display_date_short":null,
  "display_date_label":"datum onbekend","created_date_short":null,"created_date_label":null,
  "created_by":null,"text":"","lead":"Beschikbare intro.","location":null,"city":null}]}]}]])
assert(table.concat(duplicates.report_lines(nulls), '\n'):find('datum onbekend', 1, true))
duplicates.show(nulls, function() end)
buf = vim.api.nvim_get_current_buf()
key(buf, '<CR>')
local null_text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(null_text:find('Beschikbare intro.', 1, true))
assert(not null_text:find('NIL', 1, true) and not null_text:find('Aangemaakt:', 1, true))
key(buf, 'q'); key(buf, 'q')
print('duplicate report presentation: OK')
