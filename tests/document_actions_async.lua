local ai = require('ai_text')
local jobs = require('buffer_jobs')
local native = vim.system
local requests = {}
vim.system = function(command, options, done)
  assert(type(done) == 'function', 'documentactie blokkeert via wait')
  requests[#requests + 1] = { command = command, options = options, done = done }
  return {}
end
local function await(predicate) assert(vim.wait(1000, predicate)) end
local function buffer(explicit)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { explicit and 'e: B' or '',
    '=== ARTIKEL ===', '', 'Kop', '', 'Een oorspronkelijke alinea.' })
  return buf
end
for _, explicit in ipairs({ false, true }) do
  requests = {}
  local buf = buffer(explicit)
  local completed
  ai._edition_autodetect(buf, table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'),
    function(ok) completed = ok end)
  assert(#requests == 1)
  requests[1].done({ code = 0, stdout = vim.json.encode({ editions = { 'B' }, has_explicit_editions = explicit,
    detection = { confidence = 'high', editions = { 'B' }, suggested_dateline = 'Kampen' } }) })
  await(function() return #requests == 2 end)
  assert(requests[2].options.timeout == 3000 and jobs.count(buf) > 0)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere eigen tekst.' })
  local latest = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  requests[2].done({ code = 0, stdout = 'VEROUDERD RESULTAAT' })
  await(function() return completed ~= nil and jobs.count(buf) == 0 end)
  assert(completed == false and #requests == 2)
  assert(vim.deep_equal(latest, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'late documentactie overschreef edits')
end
requests = {}
local buf = buffer(true)
local completed
ai.tussenkopjes_streamer({ buf = buf, automatic = true, done = function(ok) completed = ok end })
assert(#requests == 1 and requests[1].command[2] == 'inspect')
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere tekst tijdens inspectie.' })
requests[1].done({ code = 0, stdout = '{"has_headline":true,"automatic_structure":true}' })
await(function() return completed ~= nil and jobs.count(buf) == 0 end)
assert(not completed and #requests == 1 and not vim.b[buf].article_structure_running,
  'verouderde inspectie startte AI of liet de poort hangen')
vim.system = native
print('document actions async: OK')
