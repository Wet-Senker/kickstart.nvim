package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require('ai_text')
local original_runner = ai._edition_variant_runner
local review = ai._edition_review
local original_create = review.create_rewrite_workspace
local original_system = vim.system
local buf = vim.api.nvim_create_buf(false, true)
local source = 'Originele kop\n\nBronbody.'
local general = 'Regionale kop\n\n**OVERIJSSEL - Regionale intro.**\n\nBody.'
local local_text = 'Lokale kop\n\n**KAMPEN - Lokale intro.**\n\nBody.'
local marker = 'GEEN_LOKALE_INVALSHOEK'
local captured

review.create_rewrite_workspace = function(_, expected_source, codes, _, tasks, results, general_content, done)
  -- Echte Python-kern: de clienttest bevat zelf geen terugval- of groepsregels.
  local result = original_system({ require('texttools_commands').bin('python'),
    '-m', 'texttools.edition_versions_cli', 'create-from-rewrites' }, {
    text = true,
    stdin = vim.json.encode({ markdown = '=== ARTIKEL ===\n\n' .. source,
      expected_source = expected_source, editions = codes, tasks = tasks,
      results = results, general_content = general_content }),
  }):wait(5000)
  assert(result.code == 0, result.stderr)
  local decoded = vim.json.decode(result.stdout)
  if decoded.state == 'needs_general' then
    done(false, nil, decoded.task)
    return
  end
  captured = { variants = {}, groups = {} }
  for _, variant in ipairs(decoded.workspace.variants) do
    local destinations = variant.editions or { variant.code }
    for _, code in ipairs(destinations) do captured.variants[code] = variant.content end
    if #destinations > 1 then table.insert(captured.groups, destinations) end
  end
  done(true, decoded.workspace)
end

local function run(codes, tasks, responses)
  local calls = {}
  captured = nil
  ai._edition_variant_runner = function(_, code, origin, done, task)
    assert(origin == source, 'variant kreeg niet de onbewerkte bron')
    table.insert(calls, { code = code, prompt = task.prompt })
    local response = responses[task.prompt .. ':' .. code]
    assert(response, 'onverwachte AI-taak: ' .. task.prompt .. ':' .. code)
    if response == 'decline' then
      assert(task.no_local_angle_marker == marker, 'alleen gerichte taken mogen afzien van een lokale invalshoek')
      done(true, nil, nil, true)
    elseif response == 'error' then
      done(false, nil, 'bewuste testfout')
    else
      done(true, response)
    end
  end
  ai._generate_edition_versions(buf, source, source, codes, nil, tasks, nil)
  return calls
end

local tasks = {
  { code = 'SW', editions = { 'SW' }, prompt = 'krantversie', no_local_angle_marker = marker },
  { code = 'B', editions = { 'B', 'ST' }, prompt = 'krantversie_algemeen', areas = {} },
}
local calls = run({ 'B', 'SW', 'ST' }, tasks, {
  ['krantversie:SW'] = 'decline',
  ['krantversie_algemeen:B'] = general,
})
assert(#calls == 2, 'bestaande algemene tekst moet zonder extra AI-call hergebruikt worden')
assert(captured and captured.variants.B == general and captured.variants.SW == general
  and captured.variants.ST == general, 'terloopse plaats kreeg niet de gedeelde regionale tekst')
assert(table.concat(captured.groups[1], ',') == 'B,SW,ST', 'teruggevallen editie werd niet aan de groep toegevoegd')

calls = run({ 'B', 'SW', 'ST' }, tasks, {
  ['krantversie:SW'] = local_text,
  ['krantversie_algemeen:B'] = general,
})
assert(#calls == 2 and captured.variants.SW == local_text, 'zinvolle lokale versie ging verloren')
assert(table.concat(captured.groups[1], ',') == 'B,ST', 'algemene groep werd onterecht uitgebreid')

local all_local = {
  { code = 'B', editions = { 'B' }, prompt = 'krantversie', no_local_angle_marker = marker },
  { code = 'SW', editions = { 'SW' }, prompt = 'krantversie', no_local_angle_marker = marker },
}
calls = run({ 'B', 'SW' }, all_local, {
  ['krantversie:B'] = 'decline',
  ['krantversie:SW'] = 'decline',
  ['krantversie_algemeen:B'] = general,
})
assert(#calls == 3, 'zonder bestaande algemene tekst ontbreekt de veilige fallback-AI-call')
assert(captured.variants.B == general and captured.variants.SW == general,
  'algemene fallback werd niet aan beide edities gekoppeld')
assert(table.concat(captured.groups[1], ',') == 'B,SW', 'twee teruggevallen edities delen geen reviewbuffer')

calls = run({ 'B', 'SW' }, all_local, {
  ['krantversie:B'] = 'decline',
  ['krantversie:SW'] = 'decline',
  ['krantversie_algemeen:B'] = 'error',
})
assert(not captured and #calls == 3, 'mislukte regionale fallback mag geen gedeeltelijke versies invoegen')

calls = run({ 'B', 'SW' }, all_local, {
  ['krantversie:B'] = 'error',
  ['krantversie:SW'] = local_text,
})
assert(not captured and #calls == 2, 'gedeeltelijk mislukte generatie werd toch toegepast')

ai._edition_variant_runner = original_runner
local command_args, declined_result
vim.system = function(command, _, callback)
  command_args = command
  callback { code = 0, stdout = marker .. '\n', stderr = '' }
  return { kill = function() end, is_closing = function() return false end }
end
ai._edition_variant_runner(buf, 'SW', source, function(ok, variant, err, declined)
  declined_result = { ok = ok, variant = variant, err = err, declined = declined }
end, tasks[1])
assert(vim.wait(1000, function() return declined_result ~= nil end, 20),
  'AI-marker werd niet teruggegeven aan de herschrijfroute')
assert(vim.tbl_contains(command_args, '--optional-local-angle'),
  'gerichte AI-call miste de optionele lokale invalshoek')
assert(declined_result.ok and declined_result.declined and declined_result.variant == nil,
  'AI-marker werd niet als regionale fallback verwerkt')

-- Werkelijk Python -> JSON -> Lua-contract: JSON null is vim.NIL, niet Lua nil.
-- Gebruik de busactie die de algemene B/ST/K-taak onterecht lokaal maakte.
local strategy_result = original_system({ require('texttools_commands').bin('python'), '-c',
  'import json, sys; from texttools.rewrite_strategy import rewrite_strategies; '
    .. 'print(json.dumps(rewrite_strategies(sys.stdin.read(), ["B", "SW", "ST", "K"])))' }, {
  text = true,
  stdin = '=== ARTIKEL ===\n\nProvincie Overijssel biedt reizigers de bus als alternatief\n\n'
    .. 'OVERIJSSEL - In november gratis met buslijn 161 tussen Zwolle en Deventer. '
    .. 'De N337 tussen Olst en Den Nul is afgesloten.',
}):wait(5000)
assert(strategy_result.code == 0, strategy_result.stderr)
local strategy = vim.json.decode(strategy_result.stdout)
local selected_tasks
for _, option in ipairs(strategy.options) do
  if option.id == strategy.automatic_option_id then selected_tasks = option.tasks end
end
assert(selected_tasks and #selected_tasks == 2, 'busactie mist lokale en algemene taak')
assert(selected_tasks[2].no_local_angle_marker == vim.NIL, 'test mist werkelijke JSON-null')

-- Voer de echte argument- en promptcontrole uit; alleen de externe AI is vervangen.
local cli_stub = [[
from unittest.mock import patch
from texttools.ai_cli import main
with patch('texttools.ai_cli.run_ai_edit', return_value='Regionale kop\n\n**OVERIJSSEL - Intro.**\n\nBody.'):
    main()
]]
vim.system = function(command, options, callback)
  local cli_command = { require('texttools_commands').bin('python'), '-c', cli_stub }
  vim.list_extend(cli_command, vim.list_slice(command, 2))
  local result = original_system(cli_command, options):wait(5000)
  callback(result)
  return { kill = function() end, is_closing = function() return false end }
end
for _, task in ipairs(selected_tasks) do
  local outcome
  ai._edition_variant_runner(buf, task.code, source, function(ok, variant, err)
    outcome = { ok = ok, variant = variant, err = err }
  end, task)
  assert(vim.wait(1000, function() return outcome ~= nil end, 20), 'kranttaak bleef hangen')
  assert(outcome.ok and outcome.variant, task.prompt .. ': ' .. tostring(outcome.err))
end

ai._edition_variant_runner = original_runner
review.create_rewrite_workspace = original_create
vim.system = original_system
print('rewrite local fallback: OK')
