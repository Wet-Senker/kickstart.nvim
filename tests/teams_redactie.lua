local teams = require('teams_redactie')
local dialog = require('user_dialog')
local menus, requests, notifications = {}, {}, {}
local config = { version = 1, enabled = true, today = '2026-10-13', suggested_return_date = '2026-10-20', revisions = { SW = 'revision' },
  editions = { SW = { krant = 'De Swollenaer', email = 'old@example.nl', default_email = 'old@example.nl' } },
  recipient_choices = { { name = 'Vervanger', email = 'new@example.nl' } } }
teams._call = function(args, done) requests[#requests + 1] = args; done(args[1] == 'show' and config or { version = 1 }) end
dialog.select = function(items, opts, done) menus[#menus + 1] = { items = items, opts = opts, done = done } end
vim.notify = function(message) notifications[#notifications + 1] = message end
teams.open()
menus[1].done(menus[1].items[2])
menus[2].done(menus[2].items[2])
assert(menus[3].items[1].value == '2026-10-20', 'Python-datumvoorstel niet gebruikt')
menus[3].done(menus[3].items[1])
assert(vim.deep_equal(requests[2], { 'set-coverage', 'SW', '--email', 'new@example.nl', '--expected-revision', 'revision', '--return-on', '2026-10-20' }))
teams.open(); menus[4].done(menus[4].items[2]); menus[5].done(menus[5].items[2])
menus[6].done(menus[6].items[#menus[6].items])
assert(requests[4][#requests[4]] == '--indefinite')

teams._call = function(args, done)
  requests[#requests + 1] = args
  if args[1] == 'notices' then done({ version = 1, notices = {
    { kind = 'due', edition = 'SW', krant = 'De Swollenaer', id = 'first', email = 'new@example.nl', previous_email = 'old@example.nl', return_on = '2026-10-13' },
    { kind = 'indefinite', edition = 'K', krant = 'De Kop', email = 'sub@example.nl' },
  } }) else done(config) end
end
local before = #requests
teams.check()
assert(#requests == before + 1, 'controle heeft zonder akkoord teruggezet')
assert(menus[7].opts.required == true and menus[7].opts.native == true, 'automatische herstelvraag mag niet door Escape verdwijnen')
assert(notifications[#notifications]:find('onbepaalde tijd', 1, true))
menus[7].done(menus[7].items[2])
assert(#requests == before + 1, 'afwijzen veranderde configuratie')
teams.check(); menus[8].done(menus[8].items[1])
assert(vim.deep_equal(requests[#requests], { 'restore-coverage', 'SW', '--coverage-id', 'first' }), 'herstel niet aan snapshot gebonden')

-- Async adapter meldt errors en past geen editorbuffer aan.
local actual = require('teams_redactie')
package.loaded.teams_redactie = nil
local fresh = require('teams_redactie')
local callback
vim.system = function(cmd, opts, done)
  assert(cmd[1]:match('teams%-config$') and opts.timeout == 10000)
  callback = done
  return {}
end
local finished = false
fresh._call({ 'show' }, function(data) assert(data == nil); finished = true end)
callback({ code = 1, stderr = 'revision mismatch' })
assert(vim.wait(1000, function() return finished end, 5))
assert(notifications[#notifications]:find('mislukt', 1, true))
-- Startup heeft in headless mode geen meldingsclaim of timer; met UI wel.
package.loaded.teams_redactie = nil
local startup = require('teams_redactie')
local checks, deferred = 0, nil
local original_uis, original_defer = vim.api.nvim_list_uis, vim.defer_fn
local timer_closed = false
vim.api.nvim_list_uis = function() return {} end
vim.defer_fn = function(callback_fn, delay)
  assert(delay == 1234)
  deferred = callback_fn
  return { is_closing = function() return timer_closed end, stop = function() end, close = function() timer_closed = true end }
end
startup._call = function(args, done)
  assert(args[1] == 'notices')
  checks = checks + 1
  done({ version = 1, notices = {}, next_check_ms = 1234 })
end
startup.setup()
vim.api.nvim_exec_autocmds('VimEnter', {})
vim.wait(20, function() return false end, 5)
assert(checks == 0 and deferred == nil, 'headless startup claimt meldingen')
package.loaded.teams_redactie = nil
local interactive = require('teams_redactie')
interactive._call = startup._call
vim.api.nvim_list_uis = function() return { {} } end
interactive.setup()
vim.api.nvim_exec_autocmds('VimEnter', {})
assert(vim.wait(1000, function() return checks == 1 end, 5))
assert(type(deferred) == 'function', 'dagwisseling is niet gepland')
deferred()
assert(checks == 2 and timer_closed, 'dagwisseling controleert niet opnieuw')
vim.api.nvim_list_uis, vim.defer_fn = original_uis, original_defer
package.loaded.teams_redactie = actual
print('Teams redactie: OK')
