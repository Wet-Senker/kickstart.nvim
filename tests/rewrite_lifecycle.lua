package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end

local ai = require 'ai_text'
local original_system = vim.system
local original_duplicate_runner = ai._duplicate_stage_runner
ai._duplicate_stage_runner = function(_, done)
  done(true, { performed = true, candidates = {} })
end
local rewrite_callback
local function is_rewrite(command)
  return command[2] == 'journalistiek_schrijven' or command[2] == 'krantversie'
    or command[2] == 'krantversie_algemeen'
end
local function command_text(command)
  local result = command[2]
  for i = 3, #command do
    result = result .. ' ' .. (command[i]:sub(1, 2) == '--' and command[i] or vim.fn.shellescape(command[i]))
  end
  assert(vim.tbl_contains(command, 'auto'), 'rewrite miste intern automatisch plan')
  return result
end

vim.system = function(command, _, callback)
  if is_rewrite(command) then
    rewrite_callback = callback
    return {}
  end
  callback { code = 0, stdout = '{"editions": []}', stderr = '' }
  return {}
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'Aangeleverde kop',
  '',
  'De aangeleverde tekst.',
})
ai._mark_duplicate_check_done(buf)

ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(rewrite_callback) == 'function' end, 20),
  'herschrijfcallback werd niet gestart')

vim.api.nvim_buf_delete(buf, { force = true })
rewrite_callback {
  code = 0,
  stdout = '# Nieuwe kop\n\n**DRONTEN - Nieuwe intro.**\n',
  stderr = '',
}
local drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))

local original_choice = ai._edition_mode_choice_async
local dialog = require('user_dialog')
local original_select = dialog.select
local strategy = {
  recommended_option_id = 'targeted',
  recommendation_reason = 'Gevonden: Zwolle → De Swollenaer.',
  requires_choice = true,
  options = { { id = 'general' }, { id = 'targeted' } },
}
local selected
dialog.select = function(items, opts, done)
  assert(items[1].index == 2 and opts.format_item(items[1]):find('(advies)', 1, true),
    'advies stond niet bovenaan')
  assert(opts.native == true and opts.format_item(items[1]) == 'Gerichte varianten (advies)',
    'krantmenu gebruikt niet de compacte, ombrekende presentatie')
  assert(opts.prompt:find('Zwolle → De Swollenaer', 1, true), 'motivatie ontbreekt')
  done(items[1])
end
ai._edition_mode_choice_async({ 'B', 'SW' }, nil, strategy, function(choice) selected = choice end)
assert(selected == 2, 'advieskeuze verwijst niet naar oorspronkelijke strategie-index')
dialog.select = function(items, _, done) done(items[2]) end
ai._edition_mode_choice_async({ 'B', 'SW' }, nil, strategy, function(choice) selected = choice end)
assert(selected == 1, 'algemene keuze werd niet doorgegeven')
dialog.select = function(_, _, done) done(nil) end
ai._edition_mode_choice_async({ 'B', 'SW' }, nil, strategy, function(choice) selected = choice end)
assert(selected == 0, 'annuleren werd als strategie beantwoord')
dialog.select = function() error('handmatige algemeen-override opende toch een menu') end
ai._edition_mode_choice_async({ 'B', 'SW' }, nil, strategy, function(choice) selected = choice end, true)
assert(selected == 1, 'handmatige algemeen-override werkte niet')
dialog.select = original_select

local original_variant_runner = ai._edition_variant_runner
local original_structure = ai.tussenkopjes_streamer
ai.tussenkopjes_streamer = function()
  error('volledige herschrijving startte onterecht automatische opmaak')
end
local function make_buffer()
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, {
    'e: B, SW', '', '=== ARTIKEL ===', '', 'Originele kop', '', 'Originele body.',
  })
  ai._mark_duplicate_check_done(target)
  return target
end

for _, mode in ipairs { 1, 2 } do
  local target = make_buffer()
  local commands, inputs, choices = {}, {}, 0
  local resolve_count, metadata_calls, variants = 0, 0, {}
  local result_callback
  ai._edition_variant_runner = function(_, code, origin, done)
    assert(origin == 'Originele kop\n\nOriginele body.', 'split kreeg niet het origineel')
    table.insert(variants, code)
    done(false, nil, 'bewuste testfout: geen reviewwerkruimte nodig')
  end
  ai._edition_mode_choice_async = function(codes, _, _, done)
    assert(table.concat(codes, ',') == 'B,SW')
    choices = choices + 1
    done(mode)
  end
  vim.system = function(command, opts, callback)
    if is_rewrite(command) then
      table.insert(commands, command_text(command))
      table.insert(inputs, opts.stdin)
      result_callback = callback
    elseif vim.tbl_contains(command, '--resolve-editions') then
      resolve_count = resolve_count + 1
      if resolve_count == 1 then assert(choices == 0, 'moduskeuze viel vóór editieresolutie') end
      callback { code = 0, stdout = '{"editions":["B","SW"],"names":["De Brug","De Swollenaer"]}', stderr = '' }
    else
      metadata_calls = metadata_calls + 1
      callback { code = 0, stdout = '', stderr = '' }
    end
    return {}
  end
  ai.rewrite_article_buffer()
  assert(vim.wait(1000, function() return choices == 1 end, 20))
  assert(#commands == (mode == 1 and 1 or 0), 'verkeerd aantal rewrite-AI-calls')
  if mode == 1 then
    local prompt = 'krantversie_algemeen --editions'
    assert(commands[1]:find(prompt, 1, true), 'verkeerd herschrijfcommando')
    if mode == 1 then assert(commands[1]:find('B,SW', 1, true)) end
    assert(inputs[1] == 'Originele kop\n\nOriginele body.', 'rewrite kreeg niet het origineel')
    result_callback { code = 0, stdout = '# Nieuwe kop\n\nNieuwe body.', stderr = '' }
    assert(vim.wait(1000, function() return metadata_calls == 1 end, 20), 'post-rewriteflow startte niet')
    assert(resolve_count == 2, 'rewrite controleerde de bestemming niet opnieuw')
    assert(#variants == 0, 'algemeen startte variantgeneratie')
    assert(table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n'):find('Nieuwe body.', 1, true))
  end
  if mode == 2 then
    assert(vim.wait(1000, function() return #variants == 2 end, 20))
    assert(vim.b[target].send_ai_rewrite_completed ~= true, 'mislukte generatie markeerde bron als herschreven')
  end
  vim.api.nvim_buf_delete(target, { force = true })
end

-- Zonder onderscheidend plaats- of provinciesignaal kiest de automatische
-- route één algemene tekst, zonder keuzemenu.
local target = make_buffer()
local automatic_command
ai._edition_mode_choice_async = original_choice
dialog.select = function() error('algemene automatische route toonde een menu') end
vim.system = function(command, _, callback)
  if is_rewrite(command) then
    automatic_command = command_text(command)
    callback { code = 1, stdout = '', stderr = 'bewuste teststop' }
  else
    callback {
      code = 0,
      stdout = '{"editions":["D","Z"],"names":["De Drontenaar","Zeewolde Actueel"],"rewrite_strategies":{"schema_version":2,"automatic_option_id":"general","options":[{"id":"general","tasks":[]}]}}',
      stderr = '',
    }
  end
  return {}
end
ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(automatic_command) == 'string' end, 20))
assert(automatic_command:find('krantversie_algemeen --editions', 1, true)
  and automatic_command:find('D,Z', 1, true), 'algemene D/Z-versie werd niet gekozen')
vim.api.nvim_buf_delete(target, { force = true })
dialog.select = original_select

-- Het echte menu wacht vóór AI-calls; annuleren of een gewijzigde bron bewaart
-- de volledige buffer, zonder dure herschrijf- of metadatacalls.
for _, change_source in ipairs({ false, true }) do
  target = make_buffer()
  ai._edition_mode_choice_async = original_choice
  local menu_done, menu_items
  dialog.select = function(items, _, done) menu_items, menu_done = items, done end
  local unexpected_calls = 0
  vim.system = function(command, _, callback)
    if vim.tbl_contains(command, '--resolve-editions') then
      callback { code = 0, stdout = vim.json.encode({ editions = { 'B', 'SW' },
        rewrite_strategies = { requires_choice = true, recommended_option_id = 'targeted',
          options = { { id = 'general', tasks = {} }, { id = 'targeted', tasks = {} } } } }), stderr = '' }
    else unexpected_calls = unexpected_calls + 1 end
    return {}
  end
  ai.rewrite_article_buffer()
  assert(vim.wait(1000, function() return menu_done ~= nil end, 20), 'modusmenu ontbreekt')
  assert(unexpected_calls == 0, 'AI startte voordat het menu beantwoord was')
  if change_source then
    vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuwe informatie.' })
    menu_done(menu_items[1])
  else menu_done(nil) end
  assert(unexpected_calls == 0, 'annuleren of verouderde keuze startte toch AI')
  local retained = table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n')
  assert(retained:find('Originele body.', 1, true), 'bron veranderd na geweigerde keuze')
  vim.api.nvim_buf_delete(target, { force = true })
end
dialog.select = original_select

-- De handmatige override gebruikt ook bij een lokaal signaal één algemene
-- versie en blijft bereikbaar via de aparte leader.
target = make_buffer()
automatic_command = nil
local override_mapping = vim.fn.maparg('<leader>aA', 'n', false, true)
assert(type(override_mapping) == 'table' and override_mapping.desc:find('algemene tekst', 1, true),
  'handmatige algemeen-override is niet vindbaar')
vim.system = function(command, _, callback)
  if is_rewrite(command) then
    automatic_command = command_text(command)
  else
    callback {
      code = 0,
      stdout = '{"editions":["B","SW"],"names":["De Brug","De Swollenaer"],"rewrite_strategies":{"schema_version":2,"automatic_option_id":"targeted","options":[{"id":"general","tasks":[]},{"id":"targeted","tasks":[]}]}}',
      stderr = '',
    }
  end
  return {}
end
ai.rewrite_article_buffer(true)
assert(vim.wait(1000, function() return type(automatic_command) == 'string' end, 20),
  'handmatige algemeen-override startte niet')
assert(automatic_command:find('krantversie_algemeen --editions', 1, true)
  and automatic_command:find('B,SW', 1, true),
  'handmatige override koos toch een gerichte variant')
vim.api.nvim_buf_delete(target, { force = true })

-- Een gewijzigde buffer tijdens de extra resolve mag geen verouderde keuze
-- of AI-call starten, ook niet op de al gecontroleerde importtak.
target = make_buffer()
local resolve_callback
local started = false
ai._edition_mode_choice_async = function() error('late moduskeuze') end
vim.system = function(command, _, callback)
  if is_rewrite(command) then started = true else resolve_callback = callback end
  return {}
end
ai.rewrite_article_buffer()
vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuwe informatie.' })
resolve_callback { code = 0, stdout = '{"editions":["B","SW"]}', stderr = '' }
drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))
assert(not started, 'rewrite startte voor een gewijzigde bron')
vim.api.nvim_buf_delete(target, { force = true })

-- Eén editie vraagt niets. Een late rewrite mag vervolgens geen body-edit wissen.
target = make_buffer()
rewrite_callback = nil
local single_command
vim.api.nvim_buf_set_lines(target, 0, 1, false, { 'e: B' })
vim.system = function(command, _, callback)
  if is_rewrite(command) then
    single_command = command_text(command)
    rewrite_callback = callback
  else
    callback {
      code = 0,
      stdout = '{"editions":["B"],"has_explicit_editions":true,"detection":{"confidence":"none","editions":[]}}',
      stderr = '',
    }
  end
  return {}
end
ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(rewrite_callback) == 'function' end, 20))
assert(single_command:find('krantversie --edition', 1, true)
  and single_command:find("'B'", 1, true), 'eenkrant-rewrite kreeg geen editiecontext')
vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Bewuste bodywijziging.' })
rewrite_callback { code = 0, stdout = '# Nieuwe kop\n\nNieuwe body.', stderr = '' }
drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))
assert(table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n'):find('Bewuste bodywijziging.', 1, true))
vim.api.nvim_buf_delete(target, { force = true })

-- Een stille De-Brug-default zonder betrouwbare tekstherkenning blijft een
-- algemene rewrite: een ontbrekende keuze mag geen lokale invalshoek afdwingen.
target = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(target)
vim.api.nvim_buf_set_lines(target, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Algemene kop', '', 'Een bericht zonder lokale plaats.',
})
ai._mark_duplicate_check_done(target)
local default_command
vim.system = function(command, _, callback)
  if is_rewrite(command) then
    default_command = command_text(command)
    callback { code = 1, stdout = '', stderr = 'bewuste teststop' }
  else
    callback {
      code = 0,
      stdout = '{"editions":["B"],"has_explicit_editions":false,"detection":{"confidence":"none","editions":[]}}',
      stderr = '',
    }
  end
  return {}
end
ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(default_command) == 'string' end, 20))
assert(default_command:find('journalistiek_schrijven', 1, true)
  and not default_command:find('krantversie', 1, true),
  'stille De-Brug-default kreeg onterecht een lokale editieprompt')
vim.api.nvim_buf_delete(target, { force = true })

ai._edition_mode_choice_async = original_choice
ai._edition_variant_runner = original_variant_runner
ai.tussenkopjes_streamer = original_structure
ai._duplicate_stage_runner = original_duplicate_runner
vim.system = original_system
print 'rewrite lifecycle: OK'
