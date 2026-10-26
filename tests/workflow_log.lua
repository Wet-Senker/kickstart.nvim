local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(repo)

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.env.TEXTTOOLS_LOG_DIR = directory

local workflow_log = require('workflow_log')
workflow_log.setup()
assert(vim.fn.exists(':TexttoolsLog') == 2, ':TexttoolsLog is niet geregistreerd')
local buf = vim.api.nvim_create_buf(false, true)
local source = directory .. '/artikel.md'
vim.api.nvim_buf_set_name(buf, source)

local token = workflow_log.start(buf, 'AI · Herschrijven', { command = 'aitext' })
local environment = workflow_log.environment(token)
assert(environment.TEXTTOOLS_RUN_ID == token.workflow_id, 'Python krijgt niet dezelfde run-id')
assert(environment.TEXTTOOLS_RUN_SOURCE == vim.fn.resolve(vim.fn.fnamemodify(source, ':p')),
  'bronpad wordt niet doorgegeven')
workflow_log.finish(token, 'succeeded', { exit_code = 0 })
workflow_log.finish(token, 'failed', { exit_code = 1 }) -- exact eenmaal afronden

local lines = vim.fn.readfile(workflow_log.log_path())
assert(#lines == 2, 'start/einde is niet exact eenmaal gelogd')
local started = vim.json.decode(lines[1])
local finished = vim.json.decode(lines[2])
assert(started.event == 'action_started' and finished.event == 'action_finished',
  'tijdlijngebeurtenissen ontbreken')
assert(started.action_id == finished.action_id, 'start en einde zijn niet gekoppeld')
assert(finished.outcome == 'succeeded', 'uitkomst ontbreekt')
assert(type(finished.duration_ms) == 'number', 'duur ontbreekt')
assert(not table.concat(lines, '\n'):find('artikelinhoud', 1, true), 'inhoud lekte in log')

local second = workflow_log.start(buf, 'Doublurecontrole')
assert(second.workflow_id == token.workflow_id, 'één artikel kreeg meerdere workflow-id’s')
workflow_log.finish(second, 'failed', { error = 'ProcessExit' })
workflow_log.decision(buf, 'Kranttijdsversie', 'website', { 'K', 'D' })
local decision = vim.json.decode(vim.fn.readfile(workflow_log.log_path())[5])
assert(decision.event == 'decision' and decision.choice == 'website', 'krantkeuze ontbreekt in log')
assert(vim.deep_equal(decision.editions, { 'K', 'D' }), 'editiecodes ontbreken in log')

-- De echte vim.system-callback is een fast event. Bestandsfuncties zoals
-- vim.fn.mkdir zijn daar verboden: de afronding moet op de mainthread landen.
local fast_token = workflow_log.start(buf, 'Snelle callback')
local timer = vim.uv.new_timer()
timer:start(0, 0, function()
  assert(vim.in_fast_event(), 'test draaide niet in een fast event')
  workflow_log.finish(fast_token, 'failed', { exit_code = 1, error = 'ProcessExit' })
  timer:close()
end)
assert(vim.wait(1000, function()
  return #vim.fn.readfile(workflow_log.log_path()) == 7
end), 'fast-event-afronding ging verloren')
local fast_finished = vim.json.decode(vim.fn.readfile(workflow_log.log_path())[7])
assert(fast_finished.action_id == fast_token.action_id, 'verkeerde actie afgerond')
assert(fast_finished.outcome == 'failed' and fast_finished.detail.exit_code == 1,
  'foutuitkomst ontbreekt')

-- Vanuit een paneel hoort :TexttoolsLog bij de bron, niet bij de toevallig
-- laatst gelogde workflow van een ander artikel.
local pane = vim.api.nvim_create_buf(false, true)
vim.b[pane].texttools_activity_source = buf
vim.api.nvim_set_current_buf(pane)
local native_system, command, callback = vim.system, nil, nil
vim.system = function(args, _, done) command, callback = args, done; return {} end
workflow_log.show()
assert(command and command[#command] == token.workflow_id, 'logboekpaneel verloor de bronfilter')
callback { code = 0, stdout = 'Veilige tijdlijn' }
assert(vim.wait(1000, function() return vim.api.nvim_get_current_buf() ~= pane end))
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, 'technisch logboek opende een split')
vim.fn.maparg('q', 'n', false, true).callback()
assert(vim.api.nvim_get_current_buf() == pane, 'technisch logboek verloor zijn terugweg')
vim.system = native_system

vim.fn.delete(directory, 'rf')
print('workflow log: OK')
