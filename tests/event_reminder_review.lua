local ai = require 'ai_text'
local marker = '<!-- texttools-reminder-review:1 -->'
local file = vim.fn.tempname() .. '.md'
local function source(legacy)
  local lines = { 'e: B', '', '=== ARTIKEL ===', '', 'Hoofdkop', '', 'Hoofdtekst.',
    '', '## Facebook', '', 'Mijn socialtekst.' }
  if legacy then vim.list_extend(lines, { '', '## Dagreminder', '', '### 2099-08-28', '', 'Eigen reminderkop', '', 'Eigen remindertekst.' }) end
  vim.fn.writefile(lines, file)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local generated = '## Dagreminder\n\n' .. marker .. '\n\n### 2099-08-28 — B — plaatsing 2099-08-28\n\nEigen reminderkop\n\nEigen remindertekst.\n\nDe best bekeken uit-tips voor de komende dagen:\n\n**Gecontroleerd concert**'
local calls, waiting = {}, nil
vim.system = function(command, opts, done)
  calls[#calls + 1] = command
  if command[2] == 'voorbereiden' then
    done { code = 0, stdout = vim.json.encode { beschikbaar = true, sites = { 'B' },
      kort = { mogelijk = false }, reminder = { mogelijk = true, dagen = { '2099-08-28' } } } }
  else
    assert(command[2] == 'teksten' and vim.tbl_contains(command, '--full-preview'))
    assert(vim.tbl_contains(command, '--reuse-reminder'), 'bestaande reminder niet behouden')
    waiting = done
  end
  return {}
end
vim.ui.select = function() error 'Bestaande reminder stelt niet opnieuw een keuzevraag' end
local buf = source(true)
local result
ai._event_prepare(buf, file, {}, { 'B' }, function(ok, err, prepared) result = { ok, err, prepared } end)
assert(vim.wait(1000, function() return waiting ~= nil end, 5))
waiting { code = 0, stdout = generated, stderr = '' }
assert(vim.wait(1000, function() return result ~= nil end, 5))
assert(result[1] and result[3], vim.inspect(result))
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
local _, count = text:gsub('## Dagreminder', '')
assert(count == 1 and text:find(marker, 1, true))
assert(text:find('Mijn socialtekst.', 1, true) and text:find('Hoofdtekst.', 1, true))
assert(text:find('Gecontroleerd concert', 1, true))
assert(table.concat(vim.fn.readfile(file), '\n'):find(marker, 1, true))
-- A late preview may not overwrite the author's newer text or the temp file.
buf = source(true); result, waiting = nil, nil
ai._event_prepare(buf, file, {}, { 'B' }, function(ok, err) result = { ok, err } end)
assert(vim.wait(1000, function() return waiting ~= nil end, 5))
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Mijn nieuwere wijziging.' })
waiting { code = 0, stdout = generated }
assert(vim.wait(1000, function() return result ~= nil end, 5))
assert(result[1] == false and result[2]:find('gewijzigd', 1, true))
text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('Mijn nieuwere wijziging.', 1, true) and not text:find(marker, 1, true))
assert(not table.concat(vim.fn.readfile(file), '\n'):find(marker, 1, true))
vim.fn.delete(file)
print('event reminder review: OK')
