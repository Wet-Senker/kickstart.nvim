local ai = require 'ai_text'

-- Doublurecontrole niet echt uitvoeren; alleen de editie-/suggestieflow toetsen.
ai._duplicate_stage_runner = function(_, callback)
  callback(true, { performed = true, candidates = {}, article_fingerprint = 'test' })
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

-- Een plaats uit een ander verspreidingsgebied (Zalk en Kampen → De Brug) die in
-- de tekst van een Zwols artikel voorkomt, moet als suggestie op de e:-regel
-- verschijnen — zonder de gekozen editie (SW) te wijzigen.
local zalk = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(zalk, 0, -1, false, {
  'e: SW', '', '=== ARTIKEL ===', '',
  'Bisschopsrede op de Spoolderberg', '',
  'ZWOLLE - De heren van Buckhorst uit Zalk en Kampen worden verwacht.',
})
ai._edition_autodetect(zalk, buffer_text(zalk))
assert(
  vim.wait(5000, function()
    return buffer_text(zalk):find('e: SW, SUGGESTIE, B', 1, true) ~= nil
  end, 20),
  'plaats uit ander verspreidingsgebied leverde geen B-suggestie op de e:-regel'
)
assert(buffer_text(zalk):find('suggestiereden:', 1, true), 'suggestiereden-regel ontbreekt')

-- Zonder plaatsen uit een ander gebied blijft de expliciete e:-regel ongemoeid.
local plain = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(plain, 0, -1, false, {
  'e: B', '', '=== ARTIKEL ===', '',
  'Campagne in Kampen', '',
  'KAMPEN - Inwoners leren signalen herkennen.',
})
ai._edition_autodetect(plain, buffer_text(plain))
assert(
  vim.wait(5000, function() return vim.b[plain].pubble_duplicate_check_completed == true end, 20),
  'controle rondde niet af'
)
assert(
  buffer_text(plain):find('SUGGESTIE', 1, true) == nil,
  'geen ander gebied genoemd, toch een suggestie toegevoegd'
)
assert(buffer_text(plain):find('e: B', 1, true), 'expliciete e:-regel verdween')

print 'edition suggestion flow: OK'
