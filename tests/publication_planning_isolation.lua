-- Echte aw-route t/m datumoverdracht, zonder AI/CMS. Dezelfde SW-telling mag
-- niet veranderen wanneer andere kranten vol zitten of de primaire krant B is.
vim.env.TEXTTOOLS_INBOX_DIR = vim.fn.tempname() .. '-planning-inbox'
vim.fn.mkdir(vim.env.TEXTTOOLS_INBOX_DIR, 'p')
local ai = require('ai_text')
local dates = require('publication_dates')
local native_review = dates.review
local codes, current, response, transferred, menu, schedule_options
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
require('editions')._set {
  { code = 'B', name = 'De Brug' }, { code = 'SW', name = 'De Swollenaer' },
  { code = 'ST', name = 'De Stadskoerier' }, { code = 'K', name = 'De Kop' },
  { code = 'Z', name = 'Zeewolde Actueel' }, { code = 'D', name = 'De Drontenaar' },
}

vim.system = function(command, options, done)
  local result
  if vim.tbl_contains(command, '--resolve-editions') then
    result = { code = 0, stdout = vim.json.encode {
      editions = codes, names = codes, has_photo = true, has_explicit_editions = true,
      text_date_check_required = true, source = 'expliciete e:-regel',
    }, stderr = '' }
  elseif command[1]:match('pubble%-schedule$') then
    assert(command[2] == table.concat(codes, ', '), 'verkeerde selectie naar de planning')
    schedule_options = options
    assert(options.env.TEXTTOOLS_RUN_ID == require('workflow_log').workflow_id(current),
      'planning krijgt niet het artikelbrede logspoor')
    assert(options.env.TEXTTOOLS_RUN_SOURCE:find('planning%-isolation'), 'bronpad ontbreekt')
    result = response
  else
    error('Onverwacht extern werk: ' .. table.concat(command, ' '))
  end
  vim.schedule(function() done(result) end)
  return { kill = function() end }
end

dates.review = function(buf, _, editions, display_dates, done)
  assert(buf == current and vim.deep_equal(editions, codes))
  transferred = display_dates
  done('cancel') -- Stop vóór iedere externe write.
end

vim.ui.select = function(items, options, done)
  menu = { items = items, options = options }
  if response.code == 0 then
    assert(items[1]:find('Aanbevolen', 1, true), 'adviesmenu ontbreekt')
    done(items[1], 1)
  else
    assert(not items[1]:find('Aanbevolen', 1, true), 'onvolledig antwoord kreeg automatisch advies')
    assert(items[1]:find('(?)', 1, true), 'onbekende bezetting werd als nul getoond')
    done(nil)
  end
end

local function run(selected, failure)
  codes, transferred, menu, schedule_options = selected, nil, nil, nil
  current = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(current)
  vim.api.nvim_buf_set_name(current, vim.fn.tempname() .. '-planning-isolation.md')
  vim.api.nvim_buf_set_lines(current, 0, -1, false, {
    'e: ' .. table.concat(codes, ', '), 'agenda: nee', '', '=== ARTIKEL ===', '',
    'Een regionaal nieuwsbericht', '', 'REGIO - Een gewone mededeling zonder datums.',
  })
  local data = {}
  local today = os.date('%Y-%m-%d')
  for _, code in ipairs(codes) do
    data[code] = { counts = { [today] = code == 'SW' and 4 or 7, ['2099-10-28'] = 0 },
      suggested = code == 'SW' and today or '2099-10-28', latest_date = vim.NIL,
      publication_dates = {} }
  end
  response = failure and { code = 1, stdout = '', stderr = 'Onvolledige telling.' }
    or { code = 0, stdout = vim.json.encode(data), stderr = '' }
  ai.pubble_send(current, true, true)
  assert(vim.wait(3000, function() return menu ~= nil end, 5), 'planningsmenu bleef uit')
  assert(schedule_options, 'planning niet gestart')
  if not failure then
    assert(vim.wait(3000, function() return transferred ~= nil end, 5), 'datums niet overgedragen')
    assert(transferred.SW == today .. ':4', 'SW kreeg een andere datum/bezetting door meerdere kranten')
    for _, code in ipairs(codes) do
      if code ~= 'SW' then assert(transferred[code] == '2099-10-28:0') end
    end
  else
    assert(transferred == nil, 'mislukte telling leidde toch tot verzending')
  end
end

run { 'SW' }
run { 'B', 'SW', 'ST', 'K' }
run { 'B', 'SW', 'ST', 'Z', 'D', 'K' }
run({ 'B', 'SW' }, true)
dates.review = native_review
print('publication planning isolation: OK')
