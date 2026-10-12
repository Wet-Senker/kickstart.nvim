-- Echte Python-opslag; alleen AI-uitvoer is gemockt. Akkoord blijft bij edits
-- en socials behouden, maar niet bij een succesvol toegepaste herschrijving.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local review = ai._edition_review
local original_system = vim.system
local source = vim.api.nvim_create_buf(false, true)
local origin = 'Regiokop\n\n**REGIO - Bronintro.**\n\nBronbody.'
local contents = {
  B = 'Brugkop\n\n**KAMPEN - Intro.**\n\nKamper body.',
  SW = 'Zwolse kop\n\n**ZWOLLE - Intro.**\n\nZwolse body.',
}
vim.api.nvim_buf_set_lines(source, 0, -1, false, vim.split(origin, '\n'))
local created
review.create_workspace(source, origin, { 'B', 'SW' }, {}, contents, function(ok) created = ok end)
assert(vim.wait(5000, function() return created ~= nil end), 'werkruimte maken bleef hangen')
assert(created, 'werkruimte maken mislukt')
local entries = review._review_buffers[source]
local buf = entries.B
local function sync(approve)
  local complete
  review.sync(buf, approve, function(ok) complete = ok end)
  assert(vim.wait(5000, function() return complete ~= nil end), 'sync bleef hangen')
  assert(complete, 'sync mislukt')
end
local function text(target)
  return table.concat(vim.api.nvim_buf_get_lines(target, 0, -1, false), '\n')
end
sync(true)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Kleine handmatige correctie.' })
assert(review._review_help_entry(buf).status:find('Goedgekeurd;', 1, true))
sync(false)
assert(vim.b[buf].edition_variant.status == 'approved', 'handmatige correctie trok akkoord in')
assert(vim.b[entries.SW].edition_variant.status == 'review', 'andere krant werd stil goedgekeurd')

local pending, social_calls = nil, 0
vim.system = function(command, opts, done)
  if vim.tbl_contains(command, 'texttools.edition_versions_cli') then
    return original_system(command, opts, done)
  end
  if command[2] == 'facebook_bericht' then
    social_calls = social_calls + 1
    done { code = 0, stdout = 'Facebook voor de Kamper lezers.', stderr = '' }
  elseif command[1]:match('aichat$') then
    pending = done
  elseif done then
    done { code = 1, stdout = '', stderr = 'Nacontrole buiten deze test.' }
  end
  -- Nacontroles na de rewrite zijn hier niet het onderwerp van de test;
  -- stoppen zonder echte AI, CMS of dialogen.
  return { kill = function() end }
end
vim.api.nvim_set_current_buf(buf)
ai.generate_facebook()
assert(vim.wait(1000, function() return text(buf):find('Facebook voor de Kamper lezers.', 1, true) end))
assert(social_calls == 1 and vim.b[buf].edition_requires_review ~= true, 'social trok akkoord in of startte extra AI')
sync(false)
assert(vim.b[buf].edition_variant.status == 'approved', 'social opslaan trok akkoord in')
assert(text(source):find('Facebook voor de Kamper lezers.', 1, true), 'social is niet duurzaam opgeslagen')

-- Een afgewezen laat AI-resultaat laat het bestaande akkoord ongemoeid.
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '***', 'Herschrijf het artikel.' })
ai.ai_prompt_rewrite()
assert(pending, 'rewrite startte niet')
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'Mijn handmatige nieuwe kop' })
pending { code = 0, stdout = 'Oud AI-resultaat\n\n**KAMPEN - Intro.**', stderr = '' }
assert(vim.wait(1000, function() return (tonumber(vim.b[buf].pending_jobs) or 0) == 0 end))
assert(not text(buf):find('Oud AI-resultaat', 1, true), 'laat resultaat overschreef de correctie')
assert(vim.b[buf].edition_requires_review ~= true, 'niet-toegepaste AI trok akkoord in')

pending = nil
local before_failure = text(buf)
ai.ai_prompt_rewrite()
assert(pending, 'mislukte rewrite startte niet')
pending { code = 1, stdout = '', stderr = 'Bewuste AI-testfout.' }
assert(vim.wait(1000, function() return (tonumber(vim.b[buf].pending_jobs) or 0) == 0 end))
assert(text(buf) == before_failure and vim.b[buf].edition_requires_review ~= true,
  'mislukte AI wijzigde tekst of goedkeuring')

pending = nil
ai.ai_prompt_rewrite()
assert(pending, 'tweede rewrite startte niet')
pending { code = 0, stdout = 'Nieuwe AI-kop\n\n**KAMPEN - Nieuwe intro.**\n\nNieuw verhaal.', stderr = '' }
assert(vim.wait(1000, function() return vim.b[buf].edition_requires_review == true end), 'toegepaste rewrite vroeg geen review')
assert(vim.wait(1000, function() return (tonumber(vim.b[buf].pending_jobs) or 0) == 0 end))
assert(review.send_block_reason(source):find('herschreven', 1, true), 'rewrite bleef verzendbaar')
sync(false)
assert(vim.b[buf].edition_variant.status == 'review', 'rewrite bleef na opslaan goedgekeurd')
assert(vim.b[entries.SW].edition_variant.status == 'review')
sync(true)
assert(vim.b[buf].edition_variant.status == 'approved', 'nieuwe goedkeuring faalde')
review.close(source, true)
vim.system = original_system
print 'review approval edits: OK'
