local now, serial, displayed, finished, removed = 0, 0, {}, 0, 0
package.preload['fidget.progress'] = function()
  return { handle = { create = function(spec)
    serial = serial + 1
    local handle = vim.deepcopy(spec)
    handle.token = serial
    function handle:report(update)
      for key, value in pairs(update) do self[key] = value end
    end
    function handle:finish()
      if self.done then return end
      finished = finished + 1
      self.done, self.expires_at = true, now + require('task_display').done_ttl
    end
    displayed[serial] = handle
    return handle
  end } }
end
package.preload['fidget.notification'] = function()
  return {
    remove = function(group, token)
      assert(group == 'texttools_tasks')
      removed = removed + 1
      displayed[token] = nil
    end,
    clear = function(group)
      assert(group == 'texttools_tasks')
      for token in pairs(displayed) do displayed[token] = nil end
    end,
  }
end
local display = require 'task_display'
assert(display.done_ttl == 8, 'afgeronde taken moeten acht seconden leesbaar blijven')
local config = table.concat(vim.fn.readfile('init.lua'), '\n')
assert(config:find("ttl = require('task_display').done_ttl", 1, true), 'Fidget gebruikt niet de geteste leestijd')
local buf = vim.api.nvim_get_current_buf()
local tick = vim.api.nvim_buf_get_changedtick(buf)
display.show { { key = 'a', text = 'Tekst controleren' } }
local first = displayed[1]
assert(not first.done and first.message == '')
display.complete('a', 'applied')
display.show {}
assert(displayed[1] == first and first.done and removed == 0, 'afronding werd meteen verwijderd')
assert(first.title == '✓ Tekst controleren' and first.message == '', 'bevestigde taak kreeg geen concrete resultaatregel')
now = 7
display.show {}
assert(first.expires_at == 8 and finished == 1, 'verversing verlengde/reset de vervaltijd')
-- Een nieuwe run heeft een eigen Fidget-token; oude expiratie raakt haar niet.
display.show { { key = 'a', text = 'Tekst controleren' } }
assert(displayed[2] and not displayed[2].done)
now = 8
for token, handle in pairs(displayed) do
  if handle.expires_at and handle.expires_at <= now then displayed[token] = nil end
end
assert(not displayed[1] and displayed[2], 'vervallen voltooiing raakte een nieuwe run')
display.complete('a', 'applied')
display.show {}
assert(displayed[2].done)
display.hide()
assert(next(displayed) == nil, 'voltooiingen stonden vóór een keuzescherm')
vim.wait(10, function() return false end)
assert(next(displayed) == nil, 'late callback liet verborgen taken herleven')
for _, outcome in ipairs { 'unknown', 'silent' } do
  display.show { { key = 'technical', text = 'Technisch proces' } }
  local token = serial
  display.complete('technical', outcome)
  assert(not displayed[token], 'technische afronding kreeg een generieke klaar-melding')
end
assert(display.completed_text('Herschrijven') == nil, 'ontbrekende uitkomst kreeg een voltooiingslabel')
assert(vim.api.nvim_buf_get_changedtick(buf) == tick, 'taakpresentatie wijzigde het artikel')
print('task completion: OK')
