local dialog = require 'user_dialog'
local notifications = require 'texttools_notify'

local native_uis, native_notify = vim.api.nvim_list_uis, vim.notify
vim.api.nvim_list_uis = function() return { {} } end

local shown = {}
vim.notify = function(message, level, options)
  shown[#shown + 1] = { message = message, level = level, options = options }
end

local storage_error = 'Vim:E80: Error while writing: no space left on device\nE297: Write error in swap file'
local ok = pcall(dialog.run, function() error(storage_error) end)
assert(ok, 'bekende opslagfout lekte als Lua-stacktrace door')
assert(#shown == 1 and shown[1].level == vim.log.levels.ERROR,
  'opslagfout kreeg geen zichtbare foutmelding')
assert(shown[1].options.title == 'Texttools · systeemfout'
    and shown[1].message:find('onvoldoende vrije opslagruimte', 1, true)
    and shown[1].message:find('controleer de Pubble-status', 1, true),
  'opslagfout gaf geen begrijpelijke of retry-veilige uitleg')

-- Ook een brongebonden asynchrone callback gebruikt dezelfde foutgrens.
local source = vim.api.nvim_get_current_buf()
local bound = notifications.bind(source, function() error(storage_error) end)
assert(pcall(bound), 'brongebonden opslagfout lekte als Lua-stacktrace door')
assert(#shown == 2, 'brongebonden opslagfout bleef onzichtbaar')

-- Een afgebroken geregistreerde actie houdt haar sessieslot niet vast.
local calls = 0
local action = dialog.action(function()
  calls = calls + 1
  if calls == 1 then error(storage_error) end
end)
action()
action()
assert(calls == 2, 'systeemfout liet de actie permanent als actief staan')

-- Alleen de bewezen systeemfout krijgt deze vertaling; echte codefouten
-- moeten hun stacktrace en falende test blijven behouden.
local unknown_ok, unknown = pcall(dialog.run, function() error('gesimuleerde programmeerfout') end)
assert(not unknown_ok and tostring(unknown):find('gesimuleerde programmeerfout', 1, true),
  'onbekende programmeerfout werd ten onrechte verborgen')

vim.api.nvim_list_uis, vim.notify = native_uis, native_notify
print('system errors: OK')
