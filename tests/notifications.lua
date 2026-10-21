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
local fallback
vim.notify = function(message, level)
  fallback = { message = message, level = level }
end
notifications.workflow('Geen losse voortgangstoast', vim.log.levels.INFO, { kind = 'progress' })
assert(not toast, 'Voortgang verscheen als vluchtige resultaattoast')
notifications.workflow('Niet blokkeren', vim.log.levels.WARN, {
  annote = 'Test',
  ttl = 9,
})

assert(not toast, 'Fidget kreeg een resultaatmelding in plaats van alleen voortgang')
assert(fallback.message == 'Niet blokkeren' and fallback.level == vim.log.levels.WARN,
  'opstartfallback verloor bericht of niveau')

package.loaded['fidget.notification'] = nil
package.preload['fidget.notification'] = function() error('Fidget niet beschikbaar') end
vim.notify = function(message, level)
  fallback = { message = message, level = level }
end

notifications.workflow('Fallback', vim.log.levels.INFO)
assert(fallback, 'workflowmelding heeft geen fallback zonder Fidget')
assert(fallback.message == 'Fallback', 'fallback veranderde de tekst')
assert(fallback.level == vim.log.levels.INFO, 'fallback veranderde het niveau')

local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local source = vim.api.nvim_get_current_buf()
notifications.notify('Eerste resultaat', nil, { buf = source })
notifications.workflow('Tweede resultaat', nil, { buf = source })
local entries = activity.snapshot(source).entries
assert(#entries == 2 and entries[1].message == 'Eerste resultaat' and entries[2].message == 'Tweede resultaat',
  'notify en workflow gebruiken niet dezelfde terugleesbare bestemming')
assert(not toast, 'resultaten belandden alsnog in Fidget')

-- Ook vóór een kale import zonder artikelmarker wordt de bron vastgelegd.
local late = notifications.bind(nil, function() notifications.workflow('Late bronmelding') end)
local other = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(other)
late()
assert(activity.snapshot(source).entries[3].message == 'Late bronmelding', 'kale bron verloor de callbackmelding')
assert(not activity.snapshot(other), 'late melding kwam bij het toevallig actieve scherm')

vim.notify = original_notify
package.preload['fidget.notification'] = original_preload
package.loaded['fidget.notification'] = original_loaded

print('notifications: OK')
