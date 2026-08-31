package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end
package.preload['fidget.notification'] = function()
  return { notify = function() end }
end

local ai = require 'ai_text'

local original_system = vim.system
local original_notify = vim.notify
local calls = {}

vim.notify = function() end

vim.system = function(cmd, opts, callback)
  table.insert(calls, { cmd = cmd, opts = opts })
  callback {
    code = 0,
    stdout = 'Feestelijk concert\n\nKAMPEN - Het concert begint om 20.00 uur.\n',
    stderr = '',
  }
  return { kill = function() end }
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'Fantastisch feestelijk concert',
  '',
  'KAMPEN - Het indrukwekkende concert begint om 20.00 uur.',
})

ai.journalistic_neutralize()
assert(
  vim.wait(1000, function() return vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == 'Feestelijk concert' end, 10),
  'neutraliteitsresultaat werd niet in de body geplaatst'
)
assert(#calls == 1, 'neutraliteitsactie startte niet exact één AI-call')
assert(calls[1].cmd[2] == 'journalistiek_neutraliseren', 'verkeerde prompt gestart')
assert(calls[1].opts.stdin:find('Fantastisch feestelijk concert', 1, true), 'artikelbody ontbrak in AI-input')
assert(not calls[1].opts.stdin:find('e: B', 1, true), 'controlecode kwam in AI-input terecht')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'e: B', 'controlecode ging verloren bij neutraliseren')

-- Een resultaat dat na een nieuwere gebruikersbewerking arriveert, blijft weg.
vim.system = function(_, _, callback)
  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'Eigen nieuwere kop' })
  callback { code = 0, stdout = 'Oude AI-kop\n', stderr = '' }
  return { kill = function() end }
end
ai.journalistic_neutralize()
assert(
  vim.wait(1000, function() return vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == 'Eigen nieuwere kop' end, 10),
  'laat AI-resultaat overschreef een nieuwere bufferbewerking'
)

vim.system = original_system
vim.notify = original_notify

print 'journalistic neutrality: OK'
