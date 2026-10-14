package.loaded['editions'] = nil
package.loaded['krant'] = nil
local editions = require('editions')
editions._set({
  { code = 'B', name = 'De Brug', label = 'De Brug (B)',
    photo_credit_suggestions = { ['112'] = { 'Mitchell Boswijk', 'Marco Westendorp' } } },
  { code = 'SW', name = 'De Swollenaer', label = 'De Swollenaer (SW)',
    photo_credit_suggestions = {} },
})
local krant = require('krant')

local function buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function count_credit(buf, name)
  local count = 0
  for _, line in ipairs(lines(buf)) do
    if line == 'c: ' .. name then count = count + 1 end
  end
  return count
end

local brug = buffer({
  'rubriek: 112', 'e: B', '', '=== ARTIKEL ===', '', '112 KAMPEN: Kop', '', 'Tekst.',
})
assert(krant.ensure_112_photo_credit_candidates(brug, { 'B' }))
assert(lines(brug)[1] == 'c: Mitchell Boswijk' and lines(brug)[2] == 'c: Marco Westendorp',
  'beide kandidaten staan niet bovenaan het controleblok')
assert(not krant.ensure_112_photo_credit_candidates(brug, { 'B' }),
  'tweede aanroep mag kandidaten niet opnieuw toevoegen')
assert(count_credit(brug, 'Mitchell Boswijk') == 1 and count_credit(brug, 'Marco Westendorp') == 1,
  'kandidaten zijn niet idempotent')

local existing = buffer({
  'c: Eigen fotograaf', 'rubriek: 112', 'e: B', '',
  '=== ARTIKEL ===', '', '112 KAMPEN: Kop',
})
assert(not krant.ensure_112_photo_credit_candidates(existing, { 'B' }))
assert(lines(existing)[1] == 'c: Eigen fotograaf', 'bestaande credit werd gewijzigd')

local stored = buffer({
  '---', 'media:', '  credit: "Opgeslagen fotograaf"', '---', '',
  'rubriek: 112', 'e: B', '', '=== ARTIKEL ===', '', '112 KAMPEN: Kop',
})
assert(not krant.ensure_112_photo_credit_candidates(stored, { 'B' }),
  'opgeslagen frontmattercredit werd genegeerd')

local swollenaer = buffer({
  'rubriek: 112', 'e: SW', '', '=== ARTIKEL ===', '', '112 ZWOLLE: Kop',
})
assert(not krant.ensure_112_photo_credit_candidates(swollenaer, { 'SW' }),
  'De Brug-kandidaten lekken naar een andere krant')

local ordinary = buffer({
  'e: B', '', '=== ARTIKEL ===', '', 'Gewone kop', '', 'Tekst.',
})
assert(not krant.ensure_112_photo_credit_candidates(ordinary, { 'B' }),
  'gewone De Brug-kopij kreeg 112-fotocredits')

print('112 photo credits: OK')
