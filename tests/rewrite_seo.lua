package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end

local ai = require 'ai_text'

assert(ai._rewrite_seo_context({ 'rubriek: 112' }, {}, nil) == '112')
assert(ai._rewrite_seo_context({}, {}, { prefix = '112 ZWOLLE:' }) == '112')
assert(ai._rewrite_seo_context({ 'agenda: ja' }, {}, nil) == 'evenement')
assert(ai._rewrite_seo_context({}, { '## Kalender', '', 'Titel: Concert' }, nil) == 'evenement')
assert(ai._rewrite_seo_context({ 'agenda: nee' }, { '## Kalender' }, nil) == nil)
assert(ai._rewrite_seo_context({}, {}, nil) == nil)

local original_system = vim.system
local requested
vim.system = function(command, _, callback)
  requested = command
  callback {
    code = 0,
    stdout = 'SEO-kop\n\n**KAMPEN - SEO-intro.**\n\nArtikeltekst.',
    stderr = '',
  }
  return { kill = function() end }
end

local buf = vim.api.nvim_create_buf(false, true)
local completed = false
ai._edition_variant_runner(
  buf,
  'B',
  'Brontekst',
  function(ok)
    assert(ok)
    completed = true
  end,
  { prompt = 'krantversie', editions = { 'B' }, seo_context = 'evenement' }
)
assert(vim.wait(1000, function() return completed end, 20))
assert(vim.tbl_contains(requested, '--seo-context'))
assert(vim.tbl_contains(requested, 'evenement'))

vim.api.nvim_buf_delete(buf, { force = true })
vim.system = original_system
print 'rewrite seo: OK'
