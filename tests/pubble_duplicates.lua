local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(repo)

local duplicates = require('pubble_duplicates')

local result = {
  version = 1,
  history_complete = true,
  candidates = {
    {
      headline = 'Batavia gaat aan land voor groot onderhoud',
      lead = 'De Batavia wordt naar Amsterdam gesleept voor groot onderhoud.',
      text = 'Volledige tekst van het artikel.',
      publications = { 'De Brug', 'De Drontenaar' },
      variants = {
        {
          publication = 'De Brug',
          display_date_label = '19 september 2026 om 09.00 uur',
          created_date_label = '3 september 2026 om 10.42 uur',
          created_by = 'piet.deboer',
          editor_url = 'https://brugmedia.pubble.dev/articles/internet/101',
        },
        {
          publication = 'De Drontenaar',
          display_date_label = '20 september 2026 om 09.00 uur',
          created_date_label = '3 september 2026 om 10.43 uur',
          created_by = 'piet.deboer',
          editor_url = 'https://brugmedia.pubble.dev/articles/internet/202',
        },
      },
    },
  },
}

local lines, ranges = duplicates.report_lines(result)
local text = table.concat(lines, '\n')
assert(text:find('De Brug', 1, true), 'De Brug ontbreekt als rubriek')
assert(text:find('De Drontenaar', 1, true), 'De Drontenaar ontbreekt als rubriek')
assert(not text:find('3 september 2026 om 10.42 uur', 1, true), 'overzicht toont detailmetadata')
assert(not text:find('Volledige tekst van het artikel.', 1, true), 'overzicht toont volledige tekst')
assert(#ranges == 2, 'één gekoppeld artikel hoort eenmaal per krant in het overzicht')
assert(duplicates._candidate_at_cursor(ranges, ranges[1].first) == result.candidates[1], 'cursorselectie kiest verkeerde kandidaat')
assert(duplicates._entry_at_cursor(ranges, ranges[1].first).variant.publication == 'De Brug', 'kop kiest niet de juiste krantversie')
assert(duplicates._candidate_at_cursor(ranges, 1) == nil, 'rubriekkop kiest stil een artikel')
local early_lines = duplicates.report_lines(result, { approve_label = 'doorgaan met bewerken' })
assert(table.concat(early_lines, '\n'):find('doorgaan met bewerken', 1, true), 'vroege actietekst ontbreekt')

local duplicate_site = vim.deepcopy(result)
table.insert(duplicate_site.candidates[1].variants, vim.deepcopy(duplicate_site.candidates[1].variants[1]))
local _, duplicate_site_ranges = duplicates.report_lines(duplicate_site)
assert(#duplicate_site_ranges == 2, 'dezelfde kandidaat mag per krant maar één keer worden getoond')

local many = vim.deepcopy(result)
many.candidates[2] = vim.deepcopy(many.candidates[1])
many.candidates[2].headline = 'Tweede mogelijke doublure'
local multiple_lines = duplicates.report_lines(many)
local multiple_text = table.concat(multiple_lines, '\n')
assert(not multiple_text:find('Lead: De Batavia', 1, true), 'overzicht toont een lead')
assert(not multiple_text:find('Volledige tekst van het artikel.', 1, true), 'meerdere kandidaten mogen niet alle volledige teksten tonen')
local _, heading_count = multiple_text:gsub('De Brug', '')
assert(heading_count == 1, 'krantenrubriek wordt per kandidaat herhaald')

local original_system = vim.system
local original_show = duplicates.show

local callback_value = nil
local callback_data = nil
vim.system = function(_, _, callback)
  callback({ code = 0, stdout = vim.json.encode({ version = 1, history_complete = true, candidates = {} }), stderr = '' })
end
duplicates.check({ 'pubble-duplicates', 'artikel.md', '--json' }, function(value, data)
  callback_value = value
  callback_data = data
end)
assert(vim.wait(1000, function() return callback_value ~= nil end), 'lege controle gaf geen callback')
assert(callback_value == true, 'lege controle moet verzending doorlaten')
assert(type(callback_data) == 'table', 'succesvolle controle geeft resultaatstate niet terug')

local shown = false
callback_value = nil
duplicates.show = function(data, callback)
  shown = data.candidates[1].headline == result.candidates[1].headline
  callback(false)
end
vim.system = function(_, _, callback)
  callback({ code = 0, stdout = vim.json.encode(result), stderr = '' })
end
duplicates.check({ 'pubble-duplicates', 'artikel.md', '--json' }, function(value)
  callback_value = value
end)
assert(vim.wait(1000, function() return callback_value ~= nil end), 'kandidaatcontrole gaf geen callback')
assert(shown, 'kandidatenrapport werd niet geopend')
assert(callback_value == false, 'annuleren in rapport mag verzending niet doorlaten')

local original_select = vim.ui.select
local selected_options
vim.ui.select = function(items, _, callback)
  selected_options = items
  callback(items[1])
end
for _, response in ipairs({
  { code = 1, stderr = 'Pubble niet bereikbaar' },
  { code = 0, stdout = '{}' },
  { code = 0, stdout = '{"version":2,"candidates":[]}' },
}) do
  callback_value, callback_data = nil, 'unset'
  vim.system = function(_, _, callback) callback(response) end
  duplicates.check({ 'pubble-duplicates' }, function(value, data)
    callback_value, callback_data = value, data
  end, { failure_continue_label = 'Doorgaan; later opnieuw controleren' })
  assert(vim.wait(1000, function() return callback_value ~= nil end), 'fout gaf geen callback')
  assert(callback_value and callback_data == nil, 'fout werd als geslaagde controle onthouden')
  assert(selected_options[1] == 'Doorgaan; later opnieuw controleren', 'vroege fout stelt verzenden voor')
end

callback_value = nil
vim.system = function() error('Executable ontbreekt') end
duplicates.check({ 'pubble-duplicates' }, function(value) callback_value = value end)
assert(vim.wait(1000, function() return callback_value ~= nil end), 'startfout liet controle hangen')

local original_confirm = vim.fn.confirm
local confirmed = false
vim.fn.confirm = function(_, _, default)
  confirmed = true
  assert(default == 2, 'automatische fout heeft geen veilige standaard')
  return 2
end
selected_options, callback_value = nil, nil
duplicates.check({ 'pubble-duplicates' }, function(value) callback_value = value end, { automatic = true })
assert(vim.wait(1000, function() return callback_value ~= nil end), 'automatische startfout bleef hangen')
assert(confirmed and not selected_options and not callback_value, 'automatische fout gebruikte fzf of negeerde annuleren')
vim.fn.confirm = original_confirm

shown, callback_value, selected_options = false, nil, nil
vim.system = function(_, _, callback)
  callback({ code = 0, stdout = vim.json.encode(result) })
end
duplicates.check({ 'pubble-duplicates' }, function(value) callback_value = value end, {
  is_current = function() return false end,
})
assert(vim.wait(1000, function() return callback_value ~= nil end), 'verouderde controle bleef hangen')
assert(callback_value == false and not shown and not selected_options, 'verouderd resultaat werd getoond')

vim.ui.select = original_select
vim.system = original_system
duplicates.show = original_show

print('pubble_duplicates.lua tests: OK')
