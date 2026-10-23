local activity = require('article_activity')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local ai, krant = require('ai_text'), require('krant')
local native_system = vim.system
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
local original_body = "'t Is maar wat in disse stad.\n\nEen gewone alinea.\n\nAppien Floep"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'Melding: Importbewerking (zonder AI): afgebroken regels samengevoegd.', '',
  '=== ARTIKEL ===', '',
})
local function text() return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function wait(test)
  assert(vim.wait(2000, test, 10), 'tekstbewerkingsmelding ontbreekt: ' .. text()
    .. '\n' .. vim.inspect(activity.snapshot(buf)))
end
vim.system = function(command, options, done)
  if command[1]:match('article%-dateline$') then
    done { code = 0, stdout = vim.json.encode({ version = 1, markdown = options.stdin, removed_count = 0 }) }
    return { kill = function() end }
  end
  return native_system(command, options, done)
end
krant.apply_detected_rubric('leugenbankien', buf, { normalized_body = original_body }, function() end)
wait(function() return text():find('Melding: Rubriek: Leugenbankien.', 1, true) end)
assert(text():find('Melding: Import opgeschoond (zonder AI)', 1, true), 'template verloor importmelding')
assert(text():find('Appien Floep', 1, true), 'template verloor broninhoud')
local function correction(value)
  activity.record(buf, value, vim.log.levels.INFO, {
    kind = 'success', inline = true, notice_key = 'text-corrections', resolved = true,
  })
end
correction('Tekstcheck: spelling en grammatica gecontroleerd; correcties toegepast.')
wait(function() return text():find('Melding: Tekstcheck:', 1, true) end)
correction('Tekstcheck: nieuwe correcties toegepast.')
wait(function() return text():find('Melding: Tekstcheck: nieuwe correcties toegepast.', 1, true) end)
assert(not text():find('spelling en grammatica gecontroleerd', 1, true), 'oude groepsmelding stapelt op')
assert(#activity.snapshot(buf).entries >= 3, 'samenvatting verwijderde historie')
vim.system = function(command, opts, done)
  if command[2] == 'tekstcheck' then
    assert(not opts.stdin:find('Melding:', 1, true), 'werkregels kwamen in AI-input')
    done { code = 0, stdout = opts.stdin:gsub('gewone alinea', 'gecorrigeerde alinea'), stderr = '' }
    return { kill = function() end }
  end
  return native_system(command, opts, done)
end
ai.tekstcheck()
wait(function() return text():find('Taalcorrecties toegepast (<leader>ao).', 1, true) end)
assert(text():find('gecorrigeerde alinea', 1, true), 'AO-resultaat niet toegepast')

-- Echte opmaakwijzigingen leveren één precieze groepsmelding; geen fictieve kopwijziging.
local format_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(format_buf)
local body = { 'e: B', '', '=== ARTIKEL ===', '', 'Een kop', '' }
for _ = 1, 7 do
  body[#body + 1] = string.rep('Een inhoudelijke zin. ', 25)
  body[#body + 1] = ''
end
vim.api.nvim_buf_set_lines(format_buf, 0, -1, false, body)
vim.system = function(command, opts, done)
  if command[2] == 'tussenkopjes' or command[2] == 'streamer' then
    done { code = 0, stdout = command[2] == 'streamer' and 'Een streamer' or '4: Een tussenkop', stderr = '' }
    return { kill = function() end }
  end
  return native_system(command, opts, done)
end
ai.tussenkopjes_streamer { automatic = true, buf = format_buf,
  headline = { has_headline = true, automatic_structure = true } }
assert(vim.wait(2000, function()
  local value = table.concat(vim.api.nvim_buf_get_lines(format_buf, 0, -1, false), '\n')
  return value:find('Melding: Opmaak: tussenkopjes toegevoegd; streamer toegevoegd.', 1, true)
end, 10), 'opmaakmelding ontbreekt')
assert(not table.concat(vim.api.nvim_buf_get_lines(format_buf, 0, -1, false), '\n'):find('kop aangepast', 1, true))

-- Een mislukte start mag de uitgestelde resultaatroute niet actief laten hangen.
vim.system = function() error('gesimuleerde startfout') end
local ok = pcall(require('texttools_notify').system, { 'test-startfout' },
  { texttools_activity = { await_result = true } }, function() end)
assert(not ok)
assert(next(activity.snapshot(format_buf).tasks) == nil, 'startfout liet een taak actief')
vim.system = native_system
print('transformation notices: OK')
