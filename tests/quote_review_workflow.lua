-- AR/AP en parallelle krantversies: geen verworpen voorstel stil verliezen.
vim.notify = function() end
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai, client = require('ai_text'), require('quote_review')
local original_system = vim.system
local source = 'Bronkop\n\nZWOLLE - Nieuws.\n\nArd: "Ik wil graag bruggen slaan naar werelden die verder van groen staan."'
local candidate = source:gsub('Bronkop', 'Nieuwe kop'):gsub('bruggen slaan', 'mensen verbinden')
local python = require('texttools_commands').bin('python')
local function report(text, proposed)
  local result = original_system({ python, '-c', [[
import json, sys
from texttools.quote_review import prepare_quote_review
p=json.load(sys.stdin)
print(json.dumps(prepare_quote_review(p['source'], p['article']).to_dict()))
]] }, { text = true, stdin = vim.json.encode({ source = text, article = proposed }) }):wait()
  assert(result.code == 0, result.stderr)
  return result.stdout
end
local prepared = report(source, candidate)
local ai_calls, checks, post = 0, 0, 0
local original_post = ai._post_full_article_rewrite
ai._post_full_article_rewrite = function() post = post + 1 end
vim.system = function(command, opts, done)
  if command[3] == 'texttools.quote_review' then
    checks = checks + 1
    return original_system(command, opts, done)
  end
  local result
  if vim.tbl_contains(command, '--resolve-editions') then
    result = { code = 0, stdout = '{"editions":["SW"],"has_explicit_editions":true}', stderr = '' }
  else
    assert(command[2] == 'krantversie' or command[2] == 'journalistiek_schrijven'
      or vim.tbl_contains(command, '--mode'), 'onverwachte actie')
    assert(vim.tbl_contains(command, '--quote-review-json'))
    assert(opts.stdin == source, 'review kreeg andere bron')
    ai_calls = ai_calls + 1
    result = { code = 3, stdout = prepared, stderr = 'Citaat wijkt af.' }
  end
  vim.schedule(function() done(result) end)
  return { kill = function() end }
end
local function buffer(ap)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  local text = 'e: SW\nc: Fotograaf\n\n=== ARTIKEL ===\n\n' .. source
  if ap then text = text .. '\n\n***\nMaak duidelijker' end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  ai._mark_duplicate_check_done(buf)
  return buf
end
for _, mode in ipairs({ 'ar', 'ap' }) do
  local buf = buffer(mode == 'ap')
  if mode == 'ar' then ai.rewrite_article_buffer() else ai.ai_prompt_rewrite() end
  assert(vim.wait(2000, function() return client.active(buf) ~= nil end), 'geen citaatvergelijking')
  local session = client.active(buf)
  assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('bruggen slaan', 1, true))
  local calls = ai_calls
  ai.pubble_send(buf)
  assert(ai_calls == calls, 'bron toch verzonden tijdens review')
  -- Losse metagegevens en social mogen tijdens review blijven veranderen.
  vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'c: Nieuwere fotograaf' })
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Facebook', '', 'Nieuwste social.' })
  local fixed = candidate:gsub('mensen verbinden', 'bruggen slaan')
  vim.api.nvim_buf_set_lines(session.proposal, 0, -1, false, vim.split(fixed, '\n', { plain = true }))
  session.accept()
  assert(vim.wait(2500, function() return session.closed and post == (mode == 'ar' and 1 or 2) end))
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(text:find('Nieuwe kop', 1, true) and text:find('bruggen slaan', 1, true), 'voorstel niet overgenomen')
  assert(text:find('Nieuwere fotograaf', 1, true) and text:find('Nieuwste social.', 1, true), 'parallelle edits overschreven')
  assert(not vim.b[buf].texttools_pending_quote_review)
end
assert(ai_calls == 2 and checks == 2, 'onverwachte extra AI of hercontrole')
-- Parallel terugkerende krantversies worden één voor één beoordeeld.
local buf, outcomes = buffer(false), {}
ai._edition_variant_runner(buf, 'B', source, function(ok) outcomes.B = ok end)
ai._edition_variant_runner(buf, 'SW', source, function(ok) outcomes.SW = ok end)
assert(vim.wait(1500, function() return client.active(buf) ~= nil end))
local first = client.active(buf)
local opened_tab = first.tab
vim.wait(30, function() return false end)
assert(client.active(buf) == first and vim.api.nvim_tabpage_is_valid(opened_tab), 'parallelle review nam scherm over')
first.keep()
assert(vim.wait(1500, function() return client.active(buf) and client.active(buf) ~= first end))
local second = client.active(buf)
second.keep()
assert(vim.wait(1000, function() return client.active(buf) == nil end))
assert(outcomes.B == false and outcomes.SW == false, 'afgewezen versies als geldig doorgegeven')
assert(ai_calls == 4 and checks == 2)
local function reviews_in_log()
  local count = 0
  for _, line in ipairs(vim.fn.readfile(require('workflow_log').log_path())) do
    local entry = vim.json.decode(line)
    if entry.event == 'action_finished' and entry.detail and entry.detail.exit_code == 3 then
      assert(entry.outcome == 'needs_review' and not entry.detail.error, 'inhoudelijke review gelogd als procesfout')
      count = count + 1
    end
  end
  return count
end
assert(vim.wait(1000, function() return reviews_in_log() == 4 end), 'reviewpogingen ontbreken in technisch log')
vim.system, ai._post_full_article_rewrite = original_system, original_post
print('quote review workflow: OK')
