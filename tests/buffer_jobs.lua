local jobs = require('buffer_jobs')
local function buffer() return vim.api.nvim_create_buf(false, true) end
local function drain()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  assert(vim.wait(1000, function() return done end))
end
local first, other = buffer(), buffer()
local a = jobs.start(first, 'Taak A')
local b = jobs.start(first, 'Taak B')
local c = jobs.start(other, 'Taak C')
assert(jobs.count(first) == 2 and jobs.count(other) == 1)
assert(jobs.active(first)[2].action == 'Taak B')
assert(not jobs.finish({ id = a.id, buf = a.buf }), 'een nagemaakt token werd aanvaard')
assert(jobs.finish(a) and not jobs.finish(a), 'dubbele afronding veranderde de teller')
assert(jobs.count(first) == 1 and jobs.count(other) == 1)
vim.b[first].pending_jobs = 0
assert(jobs.count(first) == 1, 'de oude teller werd opnieuw autoriteit')
assert(jobs.finish(b) and jobs.count(first) == 0)
vim.api.nvim_buf_delete(other, { force = true })
assert(jobs.count(other) == 0 and not jobs.finish(c), 'laat resultaat hield een gewiste buffer vast')

-- Twee echte resolvergrenzen: late/dubbele callbacks mogen niet vroeg
-- verzenden. Afronding komt ná de bufferupdate, ook bij omgekeerde volgorde.
local ai = require('ai_text')
local buf, callbacks = buffer(), {}
local old_system = vim.system
vim.system = function(_, _, callback)
  callbacks[#callbacks + 1] = callback
  return {}
end
local sends, done_count = 0, 0
ai.pubble_send = function(target)
  assert(target == buf and jobs.count(buf) == 0)
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'Tweede resultaat')
  sends = sends + 1
end
ai._calendar_edition_resolver(buf, 'Kop', function()
  done_count = done_count + 1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Tweede resultaat' })
end)
ai._calendar_edition_resolver(buf, 'Kop', function() done_count = done_count + 1 end)
assert(jobs.count(buf) == 2)
vim.b[buf].send_requested = true
local result = { code = 0, stdout = '{"editions":["B"]}', stderr = '' }
callbacks[2](result)
callbacks[2](result)
drain()
assert(jobs.count(buf) == 1 and done_count == 1 and sends == 0)
callbacks[1](result)
callbacks[1](result)
drain()
assert(jobs.count(buf) == 0 and done_count == 2 and sends == 1)

-- Een process-startfout moet de caller informeren én zijn token afmelden.
vim.system = function() error('bewuste startfout') end
local failed = false
ai._calendar_edition_resolver(buf, 'Kop', function(value, err)
  failed = value == nil and type(err) == 'string'
end)
drain()
assert(failed and jobs.count(buf) == 0, 'startfout liet een taak hangen')
ai._duplicate_stage_runner = function() error('bewuste startfout') end
local approved
ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) approved = ok end)
drain()
assert(approved == true and jobs.count(buf) == 0 and not vim.b[buf].pubble_duplicate_check_running,
  'mislukte doublurestart hield de poort gesloten')
assert(not vim.b[buf].pubble_duplicate_checked_body,
  'doorgaan met bewerken gaf bij een mislukte controle publicatietoestemming')
vim.system = old_system
print('buffer jobs: OK')
