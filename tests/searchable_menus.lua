local test_file = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(test_file, ':h:h')

local function source(path)
  return table.concat(vim.fn.readfile(root .. '/' .. path), '\n')
end

local function assert_searchable(path, marker)
  local text = source(path)
  local at = assert(text:find(marker, 1, true), path .. ' mist menu: ' .. marker)
  local window = text:sub(math.max(1, at - 180), math.min(#text, at + 320))
  assert(window:find('searchable = true', 1, true), path .. ' is niet doorzoekbaar: ' .. marker)
end

local menus = {
  { 'lua/agenda_bron.lua', "prompt = 'Voor welke editie?'" },
  { 'lua/agenda_menu.lua', "prompt = 'Voor welke editie?'" },
  { 'lua/agenda_menu.lua', "prompt = 'Weekendbericht maken voor welke krant?'" },
  { 'lua/agenda_menu.lua', "prompt = 'Agenda online'" },
  { 'lua/agenda_page.lua', "prompt = 'Agendapagina versturen naar welke krant?'" },
  { 'lua/ai_text.lua', 'prompt = "Texttools hulp:"' },
  { 'lua/ai_text.lua', 'prompt = category.prompt' },
  { 'lua/edition_review.lua', 'prompt = "Krantversies:"' },
  { 'lua/krant.lua', "prompt = 'Rubriek zoeken (typ bijvoorbeeld honden of raads):'" },
  { 'lua/krant.lua', 'vim.ui.select(items, { prompt = prompt, searchable = true }, callback)' },
  { 'lua/pubble_duplicates.lua', "prompt = 'Welke krantversie wil je bekijken?'" },
  { 'lua/rubriek_scan.lua', "prompt = 'Welke krant(en) op rubriek scannen?'" },
  { 'lua/site_duplicates.lua', "prompt = 'Welke krant(en) op interne webdoublures controleren?'" },
  { 'lua/teams_redactie.lua', "prompt = 'Teams-meldingen eindredactie:'" },
  { 'lua/teams_redactie.lua', "prompt = 'Teams-ontvanger voor '" },
  { 'lua/weekly_most_read.lua', "prompt = 'Meestgelezen weekoverzicht voor welke krant?'" },
  { 'plugin/column_reminders.lua', "prompt = 'Planningsoverzicht voor:'" },
}

for _, menu in ipairs(menus) do assert_searchable(menu[1], menu[2]) end

local date_picker = source('lua/date_picker.lua')
assert(date_picker:find('native = true, default = selected', 1, true),
  'datumkiezer bewaart de voorgestelde beginselectie niet')
local newspaper_review = source('lua/newspaper_review.lua')
assert(newspaper_review:find('prompt = prompt, native = true', 1, true),
  'meerregelige krantbeslissing gebruikt niet langer de native presentatie')
local reminders = source('plugin/column_reminders.lua')
assert(reminders:find('native = true, -- Fuzzy pickers ondersteunen geen betrouwbare beginindex.', 1, true),
  'actuele reminder verloor zijn betrouwbare beginselectie')

print('searchable menus: OK')
