local ai = require 'ai_text'
require('article_activity').setup { preferences = vim.fn.tempname() .. '/activity.json' }
local old_system, old_runner = vim.system, ai._duplicate_stage_runner
local pending, checks, rewrites, inputs = nil, 0, 0, {}
ai._duplicate_stage_runner = function(_, callback)
  checks = checks + 1
  pending = callback
end
vim.system = dofile('tests/helpers/calendar_core.lua')(function(command, options, callback)
  if vim.tbl_contains(command, '--resolve-editions') then
    callback { code = 0, stdout = vim.json.encode { editions = { 'B' }, names = { B = 'De Brug' }, has_explicit_editions = true } }
  elseif command[2] == 'krantversie' or command[2] == 'journalistiek_schrijven' then
    rewrites = rewrites + 1
    inputs[#inputs + 1] = options.stdin
  else
    callback { code = 0, stdout = '{}', stderr = '' }
  end
  return {}
end)
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Oorspronkelijke tekst.' })
  return buf
end
local function wait(fn) assert(vim.wait(3000, fn, 10), 'bewerking bleef wachten') end
local function start(buf)
  ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function() end)
  assert(vim.b[buf].pubble_duplicate_check_running)
  ai.rewrite_article_buffer()
  wait(function() return vim.b[buf].editorial_rewrite_generation == 1 and (vim.b[buf].pending_jobs or 0) == 1 end)
  -- Laat de asynchrone editiecontrole ook zijn callback uitvoeren.
  wait(function() return ai._pending_duplicate_rewrites[buf] ~= nil end)
end
local success = { version = 1, performed = true, candidates = {} }
local buf = source()
start(buf)
assert(rewrites == 0 and checks == 1)
pending(true, success)
wait(function() return rewrites == 1 end)
assert(checks == 1, 'onnodige tweede doublurecontrole')

buf = source()
start(buf)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwe informatie.' })
pending(true, success)
wait(function() return rewrites == 2 end)
assert(inputs[2]:find('Nieuwe informatie.', 1, true), 'verouderde tekst naar AI gestuurd')

buf = source()
start(buf)
local before = rewrites
pending(false, nil)
vim.wait(150, function() return rewrites > before end, 10)
assert(rewrites == before, 'na afgebroken controle toch herschreven')

buf = source()
start(buf)
ai.rewrite_article_buffer()
vim.wait(100, function() return false end, 10)
pending(true, success)
wait(function() return rewrites == before + 1 end)
vim.wait(100, function() return rewrites > before + 1 end, 10)
assert(rewrites == before + 1, 'meerdere verzoeken startten dubbele herschrijving')

buf = source()
start(buf)
before = rewrites
vim.api.nvim_buf_delete(buf, { force = true })
pending(true, success)
vim.wait(100, function() return rewrites > before end, 10)
assert(rewrites == before, 'gesloten buffer startte alsnog een herschrijving')

vim.system, ai._duplicate_stage_runner = old_system, old_runner
print('rewrite waits for duplicates: OK')
