local agenda = require 'agenda_page'
local activity = require 'article_activity'
local notify = require 'texttools_notify'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local original_system, original_select = vim.system, vim.ui.select
local path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== AGENDAPAGINA ===', '', '## dinsdag 3 november', '', '### Concert' }, path)
local buf = vim.fn.bufadd(path)
vim.fn.bufload(buf)
vim.api.nvim_set_current_buf(buf)
vim.b[buf].agenda_page_flow = true
local mode, counts = 'create', { validate = 0, send = 0, measure = 0 }
vim.ui.select = function(items, _, done) done(items[1]) end
vim.system = function(cmd, _, done)
  local action = cmd[4]
  counts[action] = (counts[action] or 0) + 1
  if action == 'validate' then
    local result = { valid = true, errors = {}, items = 38 }
    if mode == 'existing' then result.pubble_url = 'https://brugmedia.pubble.nl/articles/newspaper/111810' end
    done { code = 0, stdout = vim.json.encode(result) }
  elseif action == 'send' then
    done { code = 0, stdout = mode == 'invalid' and 'AGENDA_PAGE_RESULT_JSON:{}'
      or 'AGENDA_PAGE_RESULT_JSON:{"newspaper_article_id":111810,"article_url":"https://brugmedia.pubble.nl/articles/newspaper/111810"}' }
  elseif action == 'measure' then
    done { code = 0, stdout = vim.json.encode { version = 1, paragraphs = 163, items = 38,
      capacity = 166, over_by = 0, remove_items_estimate = 0, message = 'Past globaal.' } }
  else error('onverwachte actie: ' .. tostring(action)) end
  return { is_closing = function() return false end }
end
notify.workflow('Oude omvangwaarschuwing', vim.log.levels.WARN, { buf = buf, action = 'Agenda · Omvang' })
vim.wait(100, function() return false end, 10)
agenda.send(buf)
local finished = vim.wait(3000, function()
  local state = activity.snapshot(buf)
  return state and state.inline['agenda-page-sent'] and not state.issues['Agenda · Omvang']
end)
assert(finished, 'succes of nieuwe omvang ontbreekt: ' .. vim.inspect({ counts = counts, state = activity.snapshot(buf) }))
local state = activity.snapshot(buf)
assert(state.inline['agenda-page-sent'].message:find('verstuurd naar Pubble', 1, true))
assert(state.inline['agenda-page-sent'].message:find('/111810', 1, true))
assert(counts.send == 1 and counts.measure == 1)
assert(vim.b[buf].agenda_page_published_url:find('/111810', 1, true))
assert(vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('verstuurd naar Pubble', 1, true)
end), 'succes is niet zichtbaar boven de agendapagina')

mode = 'existing'
agenda.send(buf)
assert(vim.wait(3000, function()
  return activity.snapshot(buf).inline['agenda-page-sent'].message:find('staat al in Pubble', 1, true)
end), 'bestaand concept mist duidelijke melding')
assert(counts.send == 1, 'bestaand concept opnieuw verzonden')
assert(activity.snapshot(buf).inline['agenda-page-sent'].message:find('niet meegestuurd', 1, true))

mode = 'invalid'
local other_path = vim.fn.tempname() .. '.md'
vim.fn.writefile({ '=== AGENDAPAGINA ===', '', '## dinsdag 3 november', '', '### Concert' }, other_path)
local other = vim.fn.bufadd(other_path)
vim.fn.bufload(other)
vim.api.nvim_set_current_buf(other)
vim.b[other].agenda_page_flow = true
agenda.send(other)
assert(vim.wait(3000, function()
  local state = activity.snapshot(other)
  return state and state.attention and state.attention.message:find('geen artikelnummer of link', 1, true)
end), 'onvolledig antwoord werd geen fout')
assert(not activity.snapshot(other).inline['agenda-page-sent'], 'onvolledig antwoord gaf succes')
vim.fn.delete(other_path)
vim.system, vim.ui.select = original_system, original_select
vim.fn.delete(path)
print 'agenda page send notice: OK'
