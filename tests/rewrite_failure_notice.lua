-- Een herhaalde afwijzing blijft zichtbaar; volledig citaatdetail in de historie.
dofile('tests/helpers/notice_clock.lua')
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local activity = require('article_activity')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local ai = require('ai_text')
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false,
  { 'e: SW', '', '=== ARTIKEL ===', '', 'Bronkop', '', 'ZWOLLE - Bron met citaten.' })
ai._mark_duplicate_check_done(buf)
local original_system, calls = vim.system, 0
vim.system = function(command, _, done)
  local result
  if vim.tbl_contains(command, '--resolve-editions') then
    result = { code = 0, stdout = '{"editions":["SW"],"has_explicit_editions":true}', stderr = '' }
  else
    assert(command[2] == 'krantversie', 'onverwachte extra actie')
    calls = calls + 1
    result = { code = 1, stdout = '', stderr = 'Technische fout: Volledige foutpassage.' }
  end
  vim.schedule(function() done(result) end)
  return { kill = function() end }
end
for attempt = 1, 2 do
  ai.rewrite_article_buffer()
  assert(vim.wait(1500, function()
    local entries = activity.snapshot(buf).entries
    return #entries == attempt and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
      :find('Herschrijven kon niet worden afgerond.', 1, true)
  end), 'herhaalde afwijzing mist zichtbare uitleg')
end
local entries = activity.snapshot(buf).entries
assert(entries[1].run_id ~= entries[2].run_id, 'nieuwe poging als oude melding behandeld')
assert(entries[2].message:find('Volledige foutpassage.', 1, true), 'citaatdetail kwijt')
assert(entries[2].message:find('probeer daarna <leader>ar opnieuw', 1, true), 'vervolgstap ontbreekt')
assert(not entries[2].message:find('controleer de genoemde bronpassage', 1, true), 'technische fout vraagt broncorrectie')
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('ZWOLLE - Bron met citaten.', 1, true), 'bron vervangen na afwijzing')
assert(calls == 2, 'extra herschrijfaanroep')
-- Ook het duurzame technische log bewaart iedere poging afzonderlijk.
local function failures()
  local found = {}
  for _, line in ipairs(vim.fn.readfile(require('workflow_log').log_path())) do
    local entry = vim.json.decode(line)
    if entry.action == 'AI · Herschrijven' and entry.event == 'action_finished'
        and entry.outcome == 'failed' then found[#found + 1] = entry end
  end
  return found
end
assert(vim.wait(1000, function() return #failures() == 2 end), 'mislukte pogingen missen in technisch log')
local failed = failures()
assert(failed[1].action_id ~= failed[2].action_id, 'pogingen samengevoegd in technisch log')
vim.system = original_system
print('rewrite failure notice: OK')
