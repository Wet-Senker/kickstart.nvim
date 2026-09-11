package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end

local ai = require 'ai_text'
local original_system = vim.system
local rewrite_callback

vim.system = function(command, _, callback)
  if command[1] == 'bash' then
    rewrite_callback = callback
    return {}
  end
  error('onverwacht extern commando in rewrite-lifecycletest')
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'Aangeleverde kop',
  '',
  'De aangeleverde tekst.',
})
vim.b[buf].pubble_duplicate_check_completed = true

ai.rewrite_article_buffer()
assert(type(rewrite_callback) == 'function', 'herschrijfcallback werd niet gestart')

vim.api.nvim_buf_delete(buf, { force = true })
rewrite_callback {
  code = 0,
  stdout = '# Nieuwe kop\n\n**DRONTEN - Nieuwe intro.**\n',
  stderr = '',
}
local drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 20))

vim.system = original_system
print 'rewrite lifecycle: OK'
