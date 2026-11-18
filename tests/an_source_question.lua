package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
ai._post_full_article_rewrite = function() end
vim.notify = function() end
for _, scenario in ipairs({ 'answer', 'cancel', 'changed' }) do
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Originele kop', '', 'Originele tekst.' })
  local calls, pending = 0, nil
  vim.ui.input = function(options, callback)
    assert(options.prompt:find('Wie is de bron', 1, true))
    pending = callback
  end
  vim.system = function(command, options, callback)
    calls = calls + 1
    if calls == 2 then
      assert(vim.list_contains(command, '--attribution-source'))
      assert(vim.list_contains(command, 'Voorbeeldvereniging'))
    end
    callback({ code = 0, stderr = '', stdout = vim.json.encode({
      version = 1, status = calls == 1 and 'needs_review' or 'ready',
      source_sha256 = vim.fn.sha256(options.stdin),
      article = calls == 1 and options.stdin or 'Nieuwe kop\n\nBewerkte tekst.',
      source_required = calls == 1,
      issues = calls == 1 and { { code = 'source', message = 'Wie is de bron?' } } or {},
    }) })
    return { kill = function() end }
  end
  ai.journalistic_neutralize()
  assert(vim.wait(1000, function() return pending ~= nil end), 'bronvraag ontbreekt')
  assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Originele tekst.', 1, true))
  if scenario == 'changed' then vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere wijziging.' }) end
  if scenario == 'cancel' then pending(nil) else pending('Voorbeeldvereniging') end
  if scenario == 'answer' then
    assert(vim.wait(1000, function()
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Bewerkte tekst.', 1, true)
    end), 'antwoord hervatte AN niet')
    assert(calls == 2)
  else
    vim.wait(50, function() return false end)
    assert(calls == 1, 'annuleren of gewijzigde bron startte toch AN')
  end
end
print('AN source question: OK')
