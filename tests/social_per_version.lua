-- Socialtekst hoort bij de afgeronde versie, niet bij de bron.
--
-- Bij splitsen blijft de bronbuffer het onherschreven importbericht bevatten.
-- Een Facebooktekst die daar wordt gemaakt, wordt dus op de ruwe tekst
-- gebaseerd. Iedere versie krijgt daarom haar eigen tekst uit haar eigen
-- artikel; kranten die één tekst delen, hebben samen één buffer en dus één post.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local edition_review = require 'edition_review'
local dialog = require 'user_dialog'

local function article_buffer(text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, '\n', { plain = true }))
  return buf
end

local original_system, original_confirm = vim.system, dialog.confirm
local original_targets = edition_review.review_targets
local calls = {}
vim.system = function(command, opts, callback)
  table.insert(calls, { command = command, stdin = opts and opts.stdin })
  return { kill = function() end }
end

local opts = { title = 'Facebook', prompt = 'facebook_bericht' }

-- 1. In een krantbuffer: alleen die versie, met haar eigen tekst.
local review_buf = article_buffer('=== ARTIKEL ===\n\nKamper kop\n\nKAMPEN - Afgeronde Kamper tekst.')
vim.b[review_buf].edition_variant = { code = 'B', editions = { 'B' }, name = 'De Brug' }
vim.b[review_buf].edition_code = 'B'
vim.api.nvim_set_current_buf(review_buf)
ai._start_social_section(opts)
assert(#calls == 1, 'niet precies één aanroep vanuit een krantbuffer')
assert(calls[1].stdin:find('Afgeronde Kamper tekst', 1, true),
  'de krantbuffer kreeg niet haar eigen tekst mee')

-- 2. Op de bron met krantversies: vragen, en dan voor iedere versie één.
calls = {}
local source = article_buffer('=== ARTIKEL ===\n\nRuwe kop\n\nREGIO - Onbewerkt persbericht.')
local kamper = article_buffer('=== ARTIKEL ===\n\nKamper kop\n\nKAMPEN - Kamper tekst.')
local algemeen = article_buffer('=== ARTIKEL ===\n\nAlgemene kop\n\nOVERIJSSEL - Algemene tekst.')
vim.b[kamper].edition_variant = { code = 'B', editions = { 'B' }, name = 'De Brug' }
vim.b[algemeen].edition_variant = {
  code = 'SW', editions = { 'SW', 'ST', 'Z' },
  name = 'Algemeen — De Swollenaer, De Stadskoerier, Zeewolde Actueel',
}
edition_review.review_targets = function()
  return {
    { code = 'B', buf = kamper, name = 'De Brug' },
    { code = 'SW', buf = algemeen, name = 'Algemeen — De Swollenaer, De Stadskoerier, Zeewolde Actueel' },
  }
end

local asked = nil
dialog.confirm = function(prompt) asked = prompt; return 1 end
vim.api.nvim_set_current_buf(source)
ai._start_social_section(opts)

assert(asked and asked:find('ruwe importtekst', 1, true),
  'de reden waarom de bron niet deugt wordt niet genoemd')
assert(asked:find('De Brug', 1, true) and asked:find('Zeewolde Actueel', 1, true),
  'de vraag noemt niet welke versies tekst krijgen')
assert(#calls == 2, 'niet één aanroep per unieke versie, maar ' .. #calls)
local stdins = { calls[1].stdin, calls[2].stdin }
table.sort(stdins)
assert(stdins[1]:find('Algemene tekst', 1, true) and stdins[2]:find('Kamper tekst', 1, true),
  'versies kregen niet hun eigen afgeronde tekst: ' .. vim.inspect(stdins))
for _, call in ipairs(calls) do
  assert(not call.stdin:find('Onbewerkt persbericht', 1, true),
    'de ruwe brontekst is alsnog naar de AI gegaan')
end

-- 3. Annuleren maakt niets.
calls = {}
dialog.confirm = function() return 2 end
ai._start_social_section(opts)
assert(#calls == 0, 'annuleren startte toch een aanroep')

-- 4. Zonder krantversies blijft de gewone flow ongewijzigd.
calls = {}
edition_review.review_targets = function() return {} end
local plain = article_buffer('=== ARTIKEL ===\n\nKop\n\nKAMPEN - Gewone tekst.')
vim.api.nvim_set_current_buf(plain)
ai._start_social_section(opts)
assert(#calls == 1 and calls[1].stdin:find('Gewone tekst', 1, true),
  'een gewoon artikel kreeg niet gewoon zijn eigen tekst')

vim.system, dialog.confirm = original_system, original_confirm
edition_review.review_targets = original_targets

print 'social per version: OK'
