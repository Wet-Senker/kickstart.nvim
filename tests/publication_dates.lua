local dates = require('publication_dates')
local dialog = require('user_dialog')
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
local file = tmp .. '/article.md'
vim.fn.writefile({ '=== ARTIKEL ===', '', 'Kop', '', 'Het duo brengt vandaag muziek uit.' }, file)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(file))
local requests, menus, results, warnings, transitions = {}, {}, {}, {}, {}
vim.system = function(cmd, opts, done)
  assert(cmd[3] == 'texttools.publication_dates_cli', 'onverwachte actie')
  requests[#requests + 1] = { cmd = cmd, opts = opts, done = done }
  return {}
end
vim.notify = function(message) warnings[#warnings + 1] = message end
dialog.select = function(items, opts, done)
  assert(opts.native == true, 'datumvraag moet een overlay zijn')
  menus[#menus + 1] = { items = items, opts = opts, done = done }
end
local function reply(index, value)
  requests[index].done({ code = 0, stdout = vim.json.encode(value) })
  vim.wait(20, function() return false end, 5)
end
local function check()
  dates.review(buf, file, { 'B' }, { B = '2026-10-09:0' }, function(action, transition)
    results[#results + 1] = action
    transitions[#results] = transition
  end)
end
local issue = { edition = 'B', message = 'Tekst spreekt over vandaag.' }
check()
assert(vim.b[buf].publication_date_review_pending)
reply(1, { version = 1, ready = false, can_confirm = true, issues = { issue } })
assert(menus[1].opts.prompt:find('vandaag', 1, true))
menus[1].done(menus[1].items[1])
assert(requests[2].cmd[#requests[2].cmd] == '--approve', 'goedkeuring moet door Python worden vastgelegd')
local editor = '---\neditorial:\n  date_approval: {plan_sha256: test}\n---\n\n=== ARTIKEL ===\n\nKop\n\nHet duo brengt vandaag muziek uit.'
reply(2, { version = 1, ready = true, approved = true, can_confirm = true, markdown = editor, editor_markdown = editor })
assert(results[#results] == 'ready' and not vim.b[buf].publication_date_review_pending)
assert(transitions[1] and require('buffer_revision').matches(buf, transitions[1].after),
  'automatische goedkeuring mist expliciete revisietransitie')
assert(table.concat(vim.fn.readfile(file), '\n'):find('date_approval', 1, true))

check()
reply(3, { version = 1, ready = false, can_confirm = false, issues = { issue } })
assert(menus[2].items[1] == 'Publicatiedatum aanpassen', 'harde datumfout mag niet bevestigbaar zijn')
menus[2].done('Tekst zelf aanpassen')
assert(results[#results] == 'edit')
check()
reply(4, { version = 1, ready = false, can_confirm = false, issues = { issue } })
menus[3].done('Publicatiedatum aanpassen')
assert(results[#results] == 'dates')

check()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Mijn nieuwere bewerking.' })
local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
reply(5, { version = 1, ready = true })
assert(results[#results] == 'cancel', 'late reactie had moeten annuleren')
assert(vim.deep_equal(current, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'late reactie overschreef tekst')
assert(warnings[#warnings]:find('Tekst gewijzigd', 1, true))
check()
requests[6].done({ code = 1, stderr = 'fout' })
assert(vim.wait(1000, function() return not vim.b[buf].publication_date_review_pending end, 5))
assert(results[#results] == 'cancel' and warnings[#warnings]:find('niets verzonden', 1, true))

-- Geen vrije stderr, exceptionecho of procesfout als gebruikersannulering.
check()
requests[#requests].done({ code = 1, stdout = vim.json.encode {
  version = 1, ready = false, error_code = 'invalid_display_dates',
}, stderr = 'GEHEIM: artikeltekst en token' })
assert(vim.wait(1000, function() return not vim.b[buf].publication_date_review_pending end, 5))
assert(warnings[#warnings]:find('publicatiedatums zijn ongeldig', 1, true))
assert(not warnings[#warnings]:find('GEHEIM', 1, true))
local entries = vim.fn.readfile(require('workflow_log').log_path())
local last = vim.json.decode(entries[#entries])
assert(last.outcome == 'failed' and last.detail.exit_code == 1)
assert(vim.json.decode(entries[#entries - 1]).reason == 'invalid_display_dates')
for _, value in ipairs({ { code = 0, stdout = 'GEHEIM' },
    { code = 0, stdout = '{"version":1}' }, { code = 124, stderr = 'GEHEIM' } }) do
  check()
  requests[#requests].done(value)
  assert(vim.wait(1000, function() return not vim.b[buf].publication_date_review_pending end, 5))
  assert(results[#results] == 'cancel' and not warnings[#warnings]:find('GEHEIM', 1, true))
end
local before_start = #requests
vim.system = function() error('GEHEIME exception') end
check()
assert(#requests == before_start and not vim.b[buf].publication_date_review_pending)
assert(warnings[#warnings]:find('kon niet starten', 1, true) and not warnings[#warnings]:find('GEHEIM', 1, true))
vim.fn.delete(tmp, 'rf')
print('publication dates: OK')
