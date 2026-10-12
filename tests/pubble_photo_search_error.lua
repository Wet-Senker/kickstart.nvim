local photos = require('pubble_photos')
local dialog = require('user_dialog')
local log = require('workflow_log')
local requests, messages, started, finished = {}, {}, {}, {}
vim.notify = function(message) table.insert(messages, message) end
vim.system = function(command, opts, done)
  requests[#requests + 1] = { command = command, options = opts, done = done }
  return {}
end
dialog.input = function(opts, done) done(opts.default) end
log.start = function(_, action, detail)
  local trace = { action = action, detail = detail }
  started[#started + 1] = trace
  return trace
end
log.with_environment = function(opts, trace)
  assert(trace.action == 'Foto · Zoeken')
  return opts
end
log.finish = function(trace, outcome, detail)
  finished[#finished + 1] = { trace = trace, outcome = outcome, detail = detail }
end
local function reply(index, data)
  requests[index].done({ code = 0, stdout = vim.json.encode(data), stderr = '' })
  vim.wait(30, function() return false end, 5)
end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
local original = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
photos.open(buf)
reply(1, { version = 1, query = 'Kampen' })
reply(2, { version = 1, photos = {}, gallery_html = '', next_offset = vim.NIL })
assert(#started == 1 and #finished == 1)
assert(finished[1].outcome == 'succeeded' and finished[1].detail.candidate_count == 0)
local picker = vim.api.nvim_get_current_buf()
local old_list = vim.api.nvim_buf_get_lines(picker, 0, -1, false)
local search = vim.fn.maparg('s', 'n', false, true)
search.callback()
requests[3].done({ code = 1, stdout = '',
  stderr = 'Pubble-zoekantwoord bevat geen geldige resultatenlijst.' })
vim.wait(30, function() return false end, 5)
assert(#started == 2 and #finished == 2, 'zoekfout is niet eenmaal gelogd')
assert(finished[2].outcome == 'failed' and finished[2].detail.reason == 'search_result_failed')
assert(messages[#messages]:find('geen geldige resultatenlijst', 1, true), 'kernfout is niet getoond')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), original), 'zoekfout wijzigde artikel')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(picker, 0, -1, false), old_list), 'zoekfout wiste vorige pagina')
print('pubble photo search error: OK')
