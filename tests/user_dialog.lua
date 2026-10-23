local dialog = require('user_dialog')
local function shown()
  assert(vim.wait(500, function()
    return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == 'editor'
  end, 5), 'overlay ontbreekt')
end
local function key(value)
  local mapping = vim.fn.maparg(value, 'n', false, true)
  assert(type(mapping.callback) == 'function', 'toets ontbreekt: ' .. value)
  mapping.callback()
end
local choice, calls = nil, 0
dialog.select({ 'Ja', 'Nee' }, { prompt = 'Import', required = true, default = 2 }, function(item)
  choice = item; calls = calls + 1
end)
shown()
local first_window = vim.api.nvim_get_current_win()
key('<Esc>')
assert(calls == 0, 'Escape beantwoordde verplichte vraag')
assert(not vim.api.nvim_win_is_valid(first_window), 'Escape liet de verplichte vraag op het scherm staan')
assert(dialog.resume(), 'uitgestelde vraag is niet hervat')
shown()
key('<C-c>')
assert(calls == 0, 'Ctrl-C beantwoordde verplichte vraag')
dialog.resume(); shown()
key('<CR>')
assert(choice == 'Nee' and calls == 1, 'expliciet antwoord ontbreekt')

dialog.select({ 'A' }, { prompt = 'Handmatig' }, function(item) choice = item; calls = calls + 1 end)
shown(); key('<Esc>')
assert(choice == nil and calls == 2, 'handmatig menu niet geannuleerd')

-- Een nieuwe import mag een publicatiedialoog in een ander tabblad uit beeld
-- duwen, maar dezelfde bronbuffer moet haar direct kunnen terughalen.
local source = vim.api.nvim_get_current_buf()
dialog.select({ 'Datum' }, { prompt = 'Publicatieplanning', native = true, source_buf = source }, function(item)
  choice = item
end)
shown()
local dialog_win = vim.api.nvim_get_current_win()
vim.cmd('tabnew')
assert(vim.api.nvim_get_current_win() ~= dialog_win, 'nieuw importtabblad werd niet geopend')
assert(dialog.focus(source), 'openstaande dialoog kon niet worden teruggehaald')
assert(vim.api.nvim_get_current_win() == dialog_win, 'focus ging niet terug naar het dialoogvenster')
key('<CR>')
assert(choice == 'Datum', 'teruggehaalde dialoog verloor haar antwoord')

dialog.select({ 'A' }, { prompt = 'Eerste' }, function(item) choice = item end)
dialog.select({ 'B' }, { prompt = 'Tweede' }, function(item) choice = item end)
shown(); key('<CR>'); shown(); key('<CR>')
assert(choice == 'B', 'wachtrij verloor vraag')

dialog.select({ 'Blijft staan' }, { prompt = 'Import', required = true }, function(item) choice = item end)
shown()
vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
assert(dialog.resume(), 'extern gesloten vraag is niet bewaard')
shown(); key('<CR>')
assert(choice == 'Blijft staan', 'extern sluiten verloor verplichte vraag')

local input_calls = 0
dialog.input({ prompt = 'Naam', default = 'Nick' }, function(item) choice = item; input_calls = input_calls + 1 end)
shown()
local input_win = vim.api.nvim_get_current_win()
local escape = vim.fn.maparg('<Esc>', 'i', false, true)
assert(type(escape.callback) == 'function', 'invoer mist Insert-Escape')
escape.callback()
assert(input_calls == 0 and vim.api.nvim_win_is_valid(input_win), 'Insert-Escape annuleerde invoer/vervolg')
local normal_escape = vim.fn.maparg('<Esc>', 'n', false, true)
assert(normal_escape.rhs == '<Nop>', 'herhaalde Escape mag geen vervolg annuleren')
key('<CR>')
assert(choice == 'Nick', 'invoer verloren')
dialog.input({ prompt = 'Verplichte invoer', default = 'Nick', required = true }, function(item) choice = item; calls = calls + 1 end)
shown(); vim.cmd('stopinsert')
local input_buf = vim.api.nvim_get_current_buf()
local draft = vim.api.nvim_buf_get_lines(input_buf, 0, -1, false)
local input_line
for index, line in ipairs(draft) do if line == 'Nick' then input_line = index end end
vim.api.nvim_buf_set_lines(input_buf, input_line - 1, input_line, false, { 'Mijn invoer' })
local before_pause = calls
vim.fn.maparg('<Esc>', 'i', false, true).callback()
assert(calls == before_pause and vim.api.nvim_buf_is_valid(input_buf), 'Escape stelde invoer onbedoeld uit')
key('<C-c>')
assert(calls == before_pause, 'uitstellen heeft invoer ingediend')
dialog.resume(); shown(); vim.cmd('stopinsert'); key('<CR>')
assert(choice == 'Mijn invoer' and calls == before_pause + 1, 'invoerdraft ging bij uitstellen verloren')
dialog.input({ prompt = 'Naam' }, function(item) choice = item end)
shown(); vim.cmd('stopinsert'); key('<C-c>')
assert(choice == nil, 'invoer niet geannuleerd')

-- Ja/nee-vragen gaan native via vim.fn.confirm: geen overlay, geen vim.wait-lus,
-- dus ze kunnen niet vastlopen in het verse-import-venster.
local original_confirm_native = vim.fn.confirm
vim.fn.confirm = function() return 2 end
assert(dialog.confirm('Vraag', '&Ja\n&Nee', 1) == 2, 'native ja/nee-vraag mislukt')
-- Een verplichte vraag negeert Escape (0) en stelt zich opnieuw tot er een echt
-- antwoord is.
local answers, calls = { 0, 0, 1 }, 0
vim.fn.confirm = function() calls = calls + 1; return table.remove(answers, 1) end
assert(dialog.confirm('Verplicht?', '&Ja', 1, true) == 1 and calls == 3,
  'verplichte vraag niet opnieuw gesteld bij Escape')
vim.fn.confirm = original_confirm_native
-- Import policies are explicit; zonder alternatief verschijnt geen modusmenu.
local ai = require('ai_text')
local original_confirm = dialog.confirm
local original_select = dialog.select
local required
dialog.confirm = function(_, _, _, policy) required = policy; return 2 end
ai._calendar_date_confirm(5); assert(required == true, 'agendavraag niet verplicht')
ai._112_confirm('112'); assert(required == true, '112-vraag niet verplicht')
ai._rubric_confirm({ candidates = {} }); assert(required == true, 'rubriekvraag niet verplicht')
ai._rubriek_confirm_simple('Sport'); assert(required == true, 'sportvraag niet verplicht')
dialog.select = function() error('algemene herschrijfroute zonder alternatief opende een keuzemenu') end
local selected
ai._edition_mode_choice_async(
  { 'B', 'SW' }, { 'Brug', 'Swollenaer' },
  { automatic_option_id = 'general', options = { { id = 'general' } } },
  function(index) selected = index end
)
assert(selected == 1, 'automatische algemene variant ontbreekt')
dialog.confirm = original_confirm
dialog.select = original_select

ai._edition_mode_choice_async(
  { 'B', 'SW' }, { 'Brug', 'Swollenaer' },
  { requires_choice = true, recommended_option_id = 'targeted',
    recommendation_reason = 'Gevonden: Zwolle → De Swollenaer.',
    options = { { id = 'general', label = 'Eén algemene versie' },
      { id = 'targeted', label = 'Gerichte varianten' } } },
  function(index) selected = index end
)
shown()
local menu_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
assert(menu_text:find('Zwolle → De Swollenaer', 1, true), 'motivatie niet zichtbaar in menu')
assert(menu_text:find('1. Gerichte varianten (advies)', 1, true), 'advies niet zichtbaar als eerste optie')
key('<CR>')
assert(selected == 2, 'Enter op aanbevolen optie koos de verkeerde strategie')

-- In de echte configuratie injecteert telescope-ui-select zijn fuzzy provider.
-- Alleen handmatige selecties gebruiken die; verplichte vragen blijven native.
local fuzzy_calls, fuzzy_choice = 0, nil
dialog.setup({
  manual_select = function(items, opts, done)
    fuzzy_calls = fuzzy_calls + 1
    assert(opts.prompt == 'Zoeken', 'fuzzy prompt niet doorgegeven')
    done(items[2], 2)
  end,
})
vim.ui.select({ 'Alpha', 'Beta' }, { prompt = 'Zoeken' }, function(item) fuzzy_choice = item end)
assert(vim.wait(500, function() return fuzzy_choice ~= nil end, 5), 'fuzzy selectie niet afgerond')
assert(fuzzy_choice == 'Beta' and fuzzy_calls == 1, 'handmatig menu gebruikte fuzzy provider niet')

dialog.select({ 'Expliciet' }, { prompt = 'Import', required = true }, function(item) choice = item end)
shown(); key('<CR>')
assert(choice == 'Expliciet' and fuzzy_calls == 1, 'verplichte vraag gebruikte fuzzy provider')

-- Met fuzzy provider ingesteld blijft dit menu leesbaar op 80 kolommen.
local previous_columns, previous_lines = vim.o.columns, vim.o.lines
vim.o.columns, vim.o.lines = 80, 24
ai._edition_mode_choice_async(
  { 'B', 'SW' }, nil,
  { requires_choice = true, recommended_option_id = 'targeted',
    recommendation_reason = 'Gevonden: Zwolle → De Swollenaer. Lokale nadruk alleen als de bron die inhoudelijk draagt.',
    options = { { id = 'general', label = string.rep('Te lange optie ', 10) },
      { id = 'targeted', label = string.rep('Te brede optie ', 10) } } },
  function(index) selected = index end
)
shown()
assert(fuzzy_calls == 1, 'krantmenu gaf motivatie aan een afkappende fuzzy prompt')
local menu_win = vim.api.nvim_get_current_win()
local compact_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local compact_text = table.concat(compact_lines, '\n')
assert(compact_text:find('Welke krantversies?', 1, true), 'compacte titel ontbreekt')
assert(compact_text:find('1. Gerichte varianten (advies)', 1, true), 'lange strategielabel niet ingekort')
assert(not compact_text:find('Te brede optie', 1, true), 'breed label bleef staan')
assert(vim.wo[menu_win].wrap, 'motivatie wordt niet omgebroken')
assert(vim.api.nvim_win_get_width(menu_win) <= 76, 'menu past niet op 80 kolommen')
local rows = 0
for _, line in ipairs(compact_lines) do
  rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / vim.api.nvim_win_get_width(menu_win)))
end
assert(rows <= vim.api.nvim_win_get_height(menu_win), 'menuhoogte verbergt tekst op 80x24')
key('<Esc>')
assert(selected == 0, 'compact krantmenu kan niet worden geannuleerd')
vim.o.columns, vim.o.lines = previous_columns, previous_lines

-- Zonder werkende optionele provider blijft de bestaande overlay beschikbaar.
dialog.setup({ manual_select = function() error('picker ontbreekt') end })
vim.ui.select({ 'Fallback' }, { prompt = 'Fallback' }, function(item) choice = item end)
shown(); key('<CR>')
assert(choice == 'Fallback', 'native fallback na pickerfout ontbreekt')
print('user dialog: OK')
