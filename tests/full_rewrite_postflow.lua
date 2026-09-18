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
local original_post_rewrite = ai._post_full_article_rewrite
local original_notify = vim.notify
local post_options

vim.notify = function() end
ai._post_full_article_rewrite = function(options)
  post_options = options
end
vim.system = function(command, opts, callback)
  assert(command[1]:match('aichat$'), 'vrije herschrijving startte een onverwacht commando')
  assert(opts.stdin:find('Oorspronkelijke kop', 1, true), 'vrije herschrijving kreeg de body niet')
  callback {
    code = 0,
    stdout = 'Nieuwe kop\n\n**ZWOLLE - Nieuwe lead.**\n',
    stderr = '',
  }
  return { kill = function() end }
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: SW', '', '=== ARTIKEL ===', '', 'Oorspronkelijke kop', '',
  'Oorspronkelijke body.', '', '***', 'Maak de lead concreter.',
})

ai.ai_prompt_rewrite()
assert(vim.wait(1000, function() return post_options ~= nil end, 20),
  'vrije herschrijving startte de gedeelde nacontrole niet')
assert(post_options.controls[1] == 'e: SW', 'vrije herschrijving verloor de editiecontrole')
assert(post_options.document:find('Nieuwe kop', 1, true), 'nacontrole kreeg de nieuwe tekst niet')
assert(post_options.original_content:find('Oorspronkelijke kop', 1, true),
  'nacontrole kreeg de oorspronkelijke tekst niet')
assert(post_options.streamer_only == nil and post_options.format == nil,
  'vrije herschrijving vroeg nog om automatische opmaak')

ai._post_full_article_rewrite = original_post_rewrite
vim.system = original_system
vim.notify = original_notify

print 'full rewrite postflow: OK'
