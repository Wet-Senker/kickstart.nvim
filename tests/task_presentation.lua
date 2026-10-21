-- Eén registratie, drie presentaties: werk, resultaten en beslissingen.
local displayed, handle_serial = {}, 0
package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function(spec)
        handle_serial = handle_serial + 1
        local handle = vim.deepcopy(spec)
        handle.token = 'task-' .. handle_serial
        function handle:report(update)
          for key, value in pairs(update) do self[key] = value end
        end
        function handle:finish() self.done = true end
        displayed[handle.token] = handle
        return handle
      end,
    },
  }
end
package.preload['fidget.notification'] = function()
  return {
    clear = function(group)
      assert(group == 'texttools_tasks')
      for token in pairs(displayed) do displayed[token] = nil end
    end,
    remove = function(group, token)
      assert(group == 'texttools_tasks', 'Taak gebruikte de verkeerde Fidget-groep')
      displayed[token] = nil
      return true
    end,
  }
end
local activity = require 'article_activity'
local log = require 'workflow_log'
local notifications = require 'texttools_notify'
local dialog = require 'user_dialog'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local function source(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. '-' .. name .. '.md')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', name, '', 'Mijn tekst.' })
  return buf
end
local function window(ft)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == ft then return win end
  end
end
local function text(win)
  return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), '\n')
end
local function task_text()
  local rows = {}
  for _, handle in pairs(displayed) do
    if not handle.done then rows[#rows + 1] = handle.title end
  end
  table.sort(rows)
  return table.concat(rows, '\n')
end
local function task_count()
  local count = 0
  for _, handle in pairs(displayed) do if not handle.done then count = count + 1 end end
  return count
end
local function wait(predicate) assert(vim.wait(2000, predicate, 10), 'Presentatie bleef hangen') end
local function settle() vim.wait(60, function() return false end) end
local a, b = source('Artikel-A'), source('Artikel-B')
vim.api.nvim_set_current_buf(a)
local editor = vim.api.nvim_get_current_win()
local tick = vim.api.nvim_buf_get_changedtick(a)
activity.toggle()
wait(function() return window('texttools_activity') end)
local before = #activity.snapshot(a).entries
local tasks = {}
for index = 1, 9 do tasks[index] = log.start(a, 'AI · Taak ' .. index) end
wait(function() return task_count() == 9 end)
assert(not window('texttools_tasks'), 'Het oude losse takenkader bestaat nog')
for _, handle in pairs(displayed) do
  assert(handle.message == '' and handle.lsp_client.name == 'texttools_tasks')
end
assert(vim.api.nvim_get_current_win() == editor and vim.api.nvim_buf_get_changedtick(a) == tick)
assert(#activity.snapshot(a).entries == before, 'Taakstarts kwamen in het resultatenlog')
notifications.workflow('Tussenstap…', nil, { buf = a, kind = 'progress' })
assert(#activity.snapshot(a).entries == before, 'Voortgang kwam alsnog in het logboek')
notifications.workflow('Technische tussenstap', nil, { buf = a, detail = true })
notifications.workflow('Geen doublures gevonden.', nil, { buf = a, kind = 'success' })
wait(function() return text(window('texttools_activity')):find('Geen doublures', 1, true) end)
assert(not text(window('texttools_activity')):find('Technische tussenstap', 1, true))
local history = #activity.snapshot(a).entries
local extra = log.start(a, tasks[1].action) -- Exacte eigen ID’s, geen decrement op een andere taak.
log.finish(tasks[1], 'failed'); log.finish(tasks[1], 'failed')
assert(#activity.snapshot(a).entries == history, 'Exitcode werd als domeinresultaat gelogd')
for index = 2, #tasks do log.finish(tasks[index], 'succeeded') end
activity.finish(a, extra.action_id)
wait(function() return task_count() == 0 end)

-- Gelijke acties bundelen, verschillende bronartikelen nooit samenvoegen.
local first = log.start(a, 'AI · Herschrijven')
local second = log.start(a, 'AI · Herschrijven')
local other = log.start(b, 'AI · Herschrijven')
wait(function() return task_count() == 2 and task_text():find('Artikel%-B') end)
assert(task_text():find('Artikel herschrijven… (2)', 1, true))
activity.toggle() -- Logboek verbergen verandert de taken niet.
wait(function() return not window('texttools_activity') end)
assert(task_count() == 2 and activity.statusline(a) == '')

-- Eén native asynchroon menu; achtergrondwerk wordt tijdelijk afgeschermd.
dialog.setup()
local answer
dialog.select({ 'Annuleren', 'Toch verzenden' }, { prompt = 'Mogelijke doublure', source_buf = a }, function(item)
  answer = item
end)
wait(function() return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative == 'editor' end)
local menu = vim.api.nvim_get_current_win()
settle()
assert(task_count() == 0, 'Taakmeldingen bleven vóór een keuze staan')
assert(next(displayed) == nil, 'Afgeronde taken bleven vóór een keuze staan')
assert(vim.api.nvim_get_current_win() == menu, 'Achtergrondwerk stal menufocus')
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(answer == 'Annuleren')
wait(function() return task_count() == 2 end)
log.finish(first, 'succeeded'); log.finish(second, 'failed'); log.finish(other, 'cancelled')
wait(function() return task_count() == 0 end)
assert(#activity.snapshot(a).entries == history, 'Afgeronde taken vervuilden het resultatenlog')

-- Een nieuwe tab toont hetzelfde werk, niet een tweede taakadministratie.
local across_tabs = log.start(a, 'AI · Herschrijven')
wait(function() return task_count() == 1 end)
vim.cmd 'tabnew'
vim.api.nvim_set_current_buf(b)
wait(function() return task_text():find('Artikel%-A') end)
assert(task_count() == 1, 'Tabwisseling maakte een tweede taakpresentatie')
vim.cmd 'tabclose'
wait(function() return task_count() == 1 end)
log.finish(across_tabs, 'succeeded')
wait(function() return task_count() == 0 end)

local closed = log.start(b, 'Foto uploaden')
wait(function() return task_count() == 1 end)
vim.api.nvim_buf_delete(b, { force = true })
settle()
assert(task_count() == 1, 'Sluiten van een artikel deed nog lopend werk verdwijnen')
log.finish(closed, 'failed')
wait(function() return task_count() == 0 end)

-- Fidget begrenst het venster; lange taaknamen veranderen het artikel niet.
vim.o.columns, vim.o.lines = 28, 14
local small = log.start(a, string.rep('Een lange taak ', 15))
wait(function() return task_count() == 1 end)
assert(task_text():find('Een lange taak', 1, true))
log.finish(small, 'succeeded')
wait(function() return task_count() == 0 end)
assert(vim.api.nvim_buf_get_changedtick(a) == tick, 'Presentatie wijzigde het artikel')

-- Ook een kale werkbuffer kan een getraceerde taak tonen zonder eerst een
-- artikelgrens te laten schrijven; de eerste-importworkflow blijft read-only.
local empty = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(empty)
local native_system, done = vim.system
vim.system = function(_, _, callback) done = callback; return {} end
notifications.system({ 'fake' }, { texttools_activity = { action = 'Agenda voorbereiden' } }, function()
  notifications.workflow('Agenda voorbereid.', nil, { kind = 'success' })
end)
wait(function() return task_count() == 1 end)
done { code = 0 }
wait(function() return task_count() == 0 end)
assert(activity.snapshot(empty).entries[1].message == 'Agenda voorbereid.')
assert(vim.api.nvim_buf_get_lines(empty, 0, -1, false)[1] == '', 'Tracking schreef een artikelgrens')
vim.system = native_system
print 'task presentation: OK'
