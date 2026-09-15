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
local rewrite_callback

vim.system = function(command, _, callback)
  if command[1] == 'bash' then
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
vim.b[buf].pubble_duplicate_check_completed = true

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
for _, test_case in ipairs {
  { index = 1, expected = 1 },
  { index = 2, expected = 2 },
  { index = 3, expected = 0 },
  { expected = 0 },
} do
  dialog.select = function(items, opts, done)
    assert(opts.default == 1, 'algemeen is niet de standaardkeuze')
    assert(items[#items] == 'Annuleren', 'expliciete annuleerknop ontbreekt')
    done(test_case.index and items[test_case.index] or nil, test_case.index)
  end
  local result
  ai._edition_mode_choice_async({ 'B', 'SW' }, nil, nil, function(choice) result = choice end)
  assert(result == test_case.expected)
end
dialog.select = original_select

-- De productiekeuze mag niet op de callback wachten: juist vanuit de
-- asynchrone editieresolutie zou een synchrone wachtlus de TUI blokkeren.
local pending_choice, deferred_result
dialog.select = function(items, _, done)
  pending_choice = function(index) done(items[index], index) end
end
ai._edition_mode_choice_async({ 'B', 'SW' }, nil, nil, function(choice)
  deferred_result = choice
end)
assert(type(pending_choice) == 'function' and deferred_result == nil,
  'editiekeuze wachtte synchroon op gebruikersinvoer')
pending_choice(2)
assert(deferred_result == 2, 'asynchrone editiekeuze ging niet verder na antwoord')
dialog.select = original_select

local original_variant_runner = ai._edition_variant_runner
local original_structure = ai.tussenkopjes_streamer
ai.tussenkopjes_streamer = function(options)
  if options.done then options.done(true) end
end
local function make_buffer()
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, {
    'e: B, SW', '', '=== ARTIKEL ===', '', 'Originele kop', '', 'Originele body.',
  })
  vim.b[target].pubble_duplicate_check_completed = true
  return target
end

for _, mode in ipairs { 1, 2, 0 } do
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
    if command[1] == 'bash' then
      table.insert(commands, command[3])
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

-- Ook een wijziging terwijl het asynchrone keuzemenu openstaat maakt de
-- editieresolutie ongeldig; de late keuze mag dan geen rewrite meer starten.
local target = make_buffer()
local mode_done, started = nil, false
ai._edition_mode_choice_async = function(_, _, _, done) mode_done = done end
vim.system = function(command, _, callback)
  if command[1] == 'bash' then started = true
  else callback { code = 0, stdout = '{"editions":["B","SW"]}', stderr = '' } end
  return {}
end
ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(mode_done) == 'function' end, 20))
vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Wijziging tijdens de keuze.' })
mode_done(1)
drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))
assert(not started, 'late moduskeuze startte een rewrite voor een gewijzigde buffer')
vim.api.nvim_buf_delete(target, { force = true })

-- Een gewijzigde buffer tijdens de extra resolve mag geen verouderde keuze
-- of AI-call starten, ook niet op de al gecontroleerde importtak.
target = make_buffer()
local resolve_callback
started = false
ai._edition_mode_choice_async = function() error('late moduskeuze') end
vim.system = function(command, _, callback)
  if command[1] == 'bash' then started = true else resolve_callback = callback end
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
vim.system = function(command, _, callback)
  if command[1] == 'bash' then rewrite_callback = callback
  else callback { code = 0, stdout = '{"editions":["B"]}', stderr = '' } end
  return {}
end
ai.rewrite_article_buffer()
assert(vim.wait(1000, function() return type(rewrite_callback) == 'function' end, 20))
vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Bewuste bodywijziging.' })
rewrite_callback { code = 0, stdout = '# Nieuwe kop\n\nNieuwe body.', stderr = '' }
drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))
assert(table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n'):find('Bewuste bodywijziging.', 1, true))
vim.api.nvim_buf_delete(target, { force = true })

ai._edition_mode_choice_async = original_choice
ai._edition_variant_runner = original_variant_runner
ai.tussenkopjes_streamer = original_structure
vim.system = original_system
print 'rewrite lifecycle: OK'
