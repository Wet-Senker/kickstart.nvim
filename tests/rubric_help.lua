local original_notify = vim.notify
local original_select = vim.ui.select
local select_calls = 0
local notice

vim.notify = function(message) notice = message end
vim.ui.select = function(items, _, callback)
  select_calls = select_calls + 1
  local wanted = select_calls == 1 and 'Rubrieken' or 'Wat wordt automatisch herkend?'
  for _, item in ipairs(items) do
    if item.label == wanted then
      callback(item)
      return
    end
  end
  error(wanted .. ' ontbreekt in het hulpmenu')
end

require('ai_text').show_meta_cheatsheet()

vim.notify = original_notify
vim.ui.select = original_select

assert(select_calls == 2, 'rubriekhulp opende niet beide menulagen')
assert(notice and notice:find('alleen kalender en 112', 1, true), 'uitleg over automatische herkenning ontbreekt')
assert(notice:find('via <leader>kt', 1, true), 'handmatige templatekeuze ontbreekt in de uitleg')
assert(notice:find('<leader>kp gebruikt alleen planning', 1, true), 'planningsgrens ontbreekt in de uitleg')

vim.cmd('runtime plugin/column_reminders.lua')
assert(vim.fn.exists(':RubriekPlanning') == 2, 'RubriekPlanning-opdracht is niet geregistreerd')

print('rubric help: OK')
