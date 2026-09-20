-- Socialtekst in een gedeelde reviewbuffer.
--
-- De oude flow blokkeerde dit ("maak eerst losse krantbuffers"). Nu een
-- gedeelde buffer weer het uitgangspunt is, moet het gewoon kunnen — maar
-- zonder krantcontext: de socialprompt kent maar één --edition, en die zou de
-- plaats van één krant centraal zetten in een tekst die ook bij de andere
-- kranten van de groep verschijnt.
local ai = require 'ai_text'

local function command_for(editions, code)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].edition_code = code
  vim.b[buf].edition_variant = { code = code, editions = editions, name = 'Test' }
  return ai._social_command('facebook_bericht', buf)
end

local shared = command_for({ 'SW', 'ST', 'Z' }, 'SW')
assert(not vim.tbl_contains(shared, '--edition'),
  'gedeelde buffer kreeg toch één krantcontext: ' .. vim.inspect(shared))

local single = command_for({ 'B' }, 'B')
assert(vim.tbl_contains(single, '--edition') and vim.tbl_contains(single, 'B'),
  'eigen krantversie kreeg geen krantcontext: ' .. vim.inspect(single))

-- Een gewone artikelbuffer zonder variant blijft werken zoals hij deed.
local plain = vim.api.nvim_create_buf(false, true)
vim.b[plain].edition_code = 'D'
local plain_command = ai._social_command('facebook_bericht', plain)
assert(vim.tbl_contains(plain_command, '--edition') and vim.tbl_contains(plain_command, 'D'),
  'gewone buffer verloor haar krantcontext')

print 'social shared buffer: OK'
