package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local dialog = require('user_dialog')
local original_system, original_select = vim.system, dialog.select
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local source = 'Ondernemersbijeenkomst\n\nOndernemers uit heel Overijssel komen in Zwolle bijeen.'
local strategy = { requires_choice = true, recommended_option_id = 'targeted',
  options = { { id = 'general', tasks = {} }, { id = 'targeted', tasks = {} } } }

-- Geen kandidaat of expliciete algemeen-override: geen beoordelingscall.
vim.system = function() error('onverwachte adviescall') end
for _, general in ipairs({ false, true }) do
  local received
  local plan = vim.deepcopy(strategy)
  plan.requires_choice = general
  ai._edition_advice_async(buf, source, { 'B', 'SW' }, plan, function(data) received = data end, general)
  assert(received == plan)
end

-- Een negatief inhoudelijk advies gaat zonder keuzemenu verder met algemeen.
local requests, received = 0, nil
local general_strategy = { requires_choice = false, assessment_status = 'assessed',
  recommended_option_id = 'general', recommendation_reason = 'Zwolle is alleen de locatie.',
  options = { { id = 'general', tasks = {} } } }
vim.system = function(command, opts, callback)
  requests = requests + 1
  assert(command[3] == 'texttools.edition_versions_cli' and command[4] == 'advise')
  assert(vim.json.decode(opts.stdin).markdown == source)
  callback { code = 0, stdout = vim.json.encode({ contract_version = 1, strategy = general_strategy }), stderr = '' }
  return { kill = function() end }
end
ai._edition_advice_async(buf, source, { 'B', 'SW' }, strategy, function(data) received = data end)
assert(vim.wait(1000, function() return received ~= nil end, 10))
dialog.select = function() error('onnodig keuzemenu bij negatief advies') end
local choice
ai._edition_mode_choice_async(nil, nil, received, function(value) choice = value end)
assert(requests == 1 and choice == 1)

-- Annulering doodt de adviesaanvraag en negeert een eventueel laat antwoord.
local pending_advice, resumed, killed = nil, false, false
vim.system = function(_, _, callback)
  pending_advice = callback
  return { kill = function() killed = true end, is_closing = function() return false end }
end
ai._edition_advice_async(buf, source, { 'B', 'SW' }, strategy, function() resumed = true end)
assert(ai.cancel_ai(buf) and killed, 'adviescall was niet annuleerbaar')
pending_advice { code = 0, stdout = vim.json.encode({ contract_version = 1, strategy = general_strategy }), stderr = '' }
vim.wait(40)
assert(not resumed, 'geannuleerd advies hervatte de workflow')

-- Het advies gaat mee in de echte schrijfopdracht en behoudt de afwijsroute.
local advice = { reason = 'Inhoudelijke bijdrage.', angle = 'Kamper ondernemer presenteert plan.',
  source_passages = { 'Kampenaar Henk presenteert een plan.' } }
local command, finished
vim.system = function(cmd, _, callback)
  command = cmd
  callback { code = 0, stdout = 'GEEN_LOKALE_INVALSHOEK', stderr = '' }
  return { kill = function() end }
end
ai._edition_variant_runner(buf, 'B', advice.source_passages[1], function(ok, _, _, declined)
  finished = ok and declined
end, { code = 'B', editions = { 'B' }, prompt = 'krantversie',
  no_local_angle_marker = 'GEEN_LOKALE_INVALSHOEK', local_angle_advice = advice })
assert(vim.wait(1000, function() return finished end, 10))
local argument = assert(vim.fn.index(command, '--local-angle-advice') >= 0)
assert(argument and vim.tbl_contains(command, '--optional-local-angle'))
local index = vim.fn.index(command, '--local-angle-advice') + 2
assert(vim.deep_equal(vim.json.decode(command[index]), advice))

-- Late beoordeling mag gewijzigde tekst/bestemmingen of een nieuw verzoek niet overschrijven.
dialog.select = function() error('verouderd advies opende een menu') end
ai._duplicate_stage_runner = function(_, done) done(true, { performed = true, candidates = {} }) end
for _, change in ipairs({ 'body', 'edition', 'generation', 'deleted' }) do
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false,
    vim.split('e: B, SW\n\n=== ARTIKEL ===\n\n' .. source, '\n', { plain = true }))
  ai._mark_duplicate_check_done(target)
  local pending, writes = nil, 0
  vim.system = function(cmd, _, callback)
    if vim.tbl_contains(cmd, '--resolve-editions') then
      callback { code = 0, stdout = vim.json.encode({ editions = { 'B', 'SW' },
        rewrite_strategies = strategy }), stderr = '' }
    elseif vim.tbl_contains(cmd, 'advise') then pending = callback
    else writes = writes + 1 end
    return { kill = function() end }
  end
  ai.rewrite_article_buffer()
  assert(vim.wait(1000, function() return pending ~= nil end, 10))
  if change == 'body' then vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuwe informatie.' })
  elseif change == 'edition' then vim.api.nvim_buf_set_lines(target, 0, 1, false, { 'e: B, ST' })
  elseif change == 'generation' then vim.b[target].editorial_rewrite_generation = 999
  else vim.api.nvim_buf_delete(target, { force = true }) end
  pending { code = 0, stdout = vim.json.encode({ contract_version = 1, strategy = general_strategy }), stderr = '' }
  vim.wait(40)
  assert(writes == 0, 'oud advies startte een rewrite')
  if vim.api.nvim_buf_is_valid(target) then vim.api.nvim_buf_delete(target, { force = true }) end
end

-- Volledig AR-pad: beoordeeld algemeen gaat zonder menu naar de echte schrijfroute;
-- een nuttig advies verschijnt eerst in het menu, zonder voortijdige herschrijving.
for _, useful in ipairs({ false, true }) do
  local target = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(target)
  vim.api.nvim_buf_set_lines(target, 0, -1, false,
    vim.split('e: B, SW\n\n=== ARTIKEL ===\n\n' .. source, '\n', { plain = true }))
  ai._mark_duplicate_check_done(target)
  local menu, rewritten, advised = false, false, 0
  dialog.select = function(_, opts, done)
    menu = true
    assert(useful and opts.prompt:find('Inhoudelijke lokale bijdrage', 1, true))
    done(nil) -- De gebruiker mag na het advies nog annuleren.
  end
  vim.system = function(cmd, _, callback)
    if vim.tbl_contains(cmd, '--resolve-editions') then
      callback { code = 0, stdout = vim.json.encode({ editions = { 'B', 'SW' },
        rewrite_strategies = strategy }), stderr = '' }
    elseif vim.tbl_contains(cmd, 'advise') then
      advised = advised + 1
      local evaluated = vim.deepcopy(general_strategy)
      if useful then
        evaluated = vim.deepcopy(strategy)
        evaluated.assessment_status = 'assessed'
        evaluated.recommendation_reason = 'Inhoudelijke lokale bijdrage gevonden.'
      end
      callback { code = 0, stdout = vim.json.encode({ contract_version = 1, strategy = evaluated }), stderr = '' }
    elseif cmd[2] == 'krantversie_algemeen' then
      rewritten = true
      callback { code = 1, stdout = '', stderr = 'bewuste teststop na advies' }
    else error('Onverwachte taak ' .. table.concat(cmd, ' ')) end
    return { kill = function() end }
  end
  ai.rewrite_article_buffer()
  assert(vim.wait(1000, function() return menu or rewritten end, 10), 'advies hervatte de workflow niet')
  assert(advised == 1 and menu == useful and rewritten ~= useful)
  assert(vim.wait(1000, function()
    local text = table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n')
    return text:find(useful and 'Inhoudelijke lokale bijdrage' or 'Zwolle is alleen de locatie', 1, true) ~= nil
  end, 10), 'advies ontbreekt boven het artikel')
  vim.api.nvim_buf_delete(target, { force = true })
end
vim.system, dialog.select = original_system, original_select
if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
print('rewrite advice: OK')
