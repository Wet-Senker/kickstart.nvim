local original_notify = vim.notify
local original_preload = package.preload['fidget.notification']
local original_loaded = package.loaded['fidget.notification']

local toast
package.loaded['fidget.notification'] = nil
package.preload['fidget.notification'] = function()
  return {
    notify = function(message, level, options)
      toast = { message = message, level = level, options = options }
    end,
  }
end

local notifications = require('texttools_notify')
notifications.workflow('Niet blokkeren', vim.log.levels.WARN, {
  annote = 'Test',
  ttl = 9,
})

assert(toast, 'workflowmelding gebruikte Fidget niet')
assert(toast.message == 'Niet blokkeren', 'workflowmelding veranderde de tekst')
assert(toast.level == vim.log.levels.WARN, 'workflowmelding veranderde het niveau')
assert(toast.options.annote == 'Test', 'workflowmelding verloor het label')
assert(toast.options.ttl == 9, 'workflowmelding verloor de zichtduur')

package.loaded['fidget.notification'] = nil
package.preload['fidget.notification'] = function() error('Fidget niet beschikbaar') end
local fallback
vim.notify = function(message, level)
  fallback = { message = message, level = level }
end

notifications.workflow('Fallback', vim.log.levels.INFO)
assert(fallback, 'workflowmelding heeft geen fallback zonder Fidget')
assert(fallback.message == 'Fallback', 'fallback veranderde de tekst')
assert(fallback.level == vim.log.levels.INFO, 'fallback veranderde het niveau')

vim.notify = original_notify
package.preload['fidget.notification'] = original_preload
package.loaded['fidget.notification'] = original_loaded

print('notifications: OK')
