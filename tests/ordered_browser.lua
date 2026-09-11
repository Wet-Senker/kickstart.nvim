package.loaded.ordered_browser = nil
local browser = require 'ordered_browser'

local original_system = vim.system
local original_open = vim.ui.open
local original_defer = vim.defer_fn

local command
vim.system = function(cmd)
  command = cmd
  return {}
end
assert(browser.open_urls({ 'https://example.test/a', 'https://example.test/b' }, {
  is_macos = true,
}))
assert(command[1] == '/usr/bin/open' and command[2] == '-g')
assert(command[3] == 'https://example.test/a')
assert(command[4] == 'https://example.test/b')

local opened = {}
local pending
vim.ui.open = function(url)
  table.insert(opened, url)
  return {}, nil
end
vim.defer_fn = function(callback, delay)
  assert(delay == 175)
  pending = callback
end
browser.open_urls({ 'https://example.test/1', 'https://example.test/2' }, {
  is_macos = false,
  delay_ms = 175,
})
assert(#opened == 1 and opened[1]:match '/1$')
assert(type(pending) == 'function')
pending()
assert(#opened == 2 and opened[2]:match '/2$')

vim.system = original_system
vim.ui.open = original_open
vim.defer_fn = original_defer

print 'ordered browser: OK'
