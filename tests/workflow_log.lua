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

vim.fn.delete(directory, 'rf')
print('workflow log: OK')
