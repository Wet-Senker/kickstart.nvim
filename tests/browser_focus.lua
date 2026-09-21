-- De browser mag de focus niet wegpakken.
--
-- Op macOS opent `ordered_browser` met `open -g`: het tabblad staat klaar
-- zonder dat de browser naar voren springt, zodat je doorwerkt in Neovim en
-- zelf bepaalt wanneer je kijkt. Wie `vim.ui.open` rechtstreeks gebruikt,
-- omzeilt dat, want dat activeert de browser wél.
local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')

-- Uitzondering: de niet-macOS-terugval binnen open_published_url zelf.
local allowed = {
  ['lua/ordered_browser.lua'] = true,
  ['lua/ai_text.lua'] = 1,
}

local offenders = {}
for _, path in ipairs(vim.fn.glob(repo_root .. '/lua/*.lua', false, true)) do
  local relative = 'lua/' .. vim.fn.fnamemodify(path, ':t')
  local seen = 0
  for _, line in ipairs(vim.fn.readfile(path)) do
    if line:find('vim.ui.open', 1, true) then seen = seen + 1 end
  end
  local budget = allowed[relative]
  if budget == true then budget = seen end
  if seen > (budget or 0) then
    table.insert(offenders, string.format('%s (%d keer, toegestaan %d)', relative, seen, budget or 0))
  end
end

assert(#offenders == 0,
  'deze modules openen de browser met focus in plaats van via ordered_browser: '
    .. table.concat(offenders, ', '))

-- En de gedeelde opener houdt zich eraan.
package.loaded.ordered_browser = nil
local browser = require 'ordered_browser'
local original_system = vim.system
local command
vim.system = function(cmd) command = cmd; return {} end
assert(browser.open_urls({ 'https://example.test/a' }, { is_macos = true }))
vim.system = original_system
assert(command[2] == '-g', 'de browser wordt op de voorgrond geopend')

print 'browser focus: OK'
