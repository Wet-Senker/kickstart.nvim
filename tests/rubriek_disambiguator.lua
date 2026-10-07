-- Vaste-titel-rubrieken krijgen bij toepassing een AI-trefwoord + aanleverdatum
-- achter de werktitel, zodat twee columns van dezelfde rubriek niet dezelfde
-- werktitel krijgen. Trefwoord en datum komen uit de metadata-stap
-- (newspaper.keyword / newspaper.planning_date). Zonder planning_date (geen
-- metadata-stap gedraaid) blijft de werktitel ongewijzigd.
local krant = require('krant')

local body = table.concat({ "'t Is maar wat in disse stad", "Appien Floep" }, "\n")

local function apply_with_fm(fm_lines)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = {}
  for _, l in ipairs(fm_lines) do table.insert(lines, l) end
  vim.list_extend(lines, { '', '=== ARTIKEL ===', '' })
  vim.list_extend(lines, vim.split(body, '\n', { plain = true }))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  krant.apply_detected_rubric('leugenbankien', buf, { normalized_body = body }, function() end)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

-- Trefwoord + planning_date → beide achter de vaste titel.
local txt = apply_with_fm({
  '---', 'newspaper:',
  '  working_title: "x - 1 OUD"',
  '  keyword: "gemeente"',
  '  planning_date: 2026-10-07',
  '---',
})
assert(txt:find('working_title: "x %- 1 LEUGENBANKIEN gemeente 2026%-10%-07"'),
  'trefwoord + datum ontbreekt: ' .. txt)

-- Alleen planning_date (geen trefwoord) → alleen de datum.
local txt2 = apply_with_fm({
  '---', 'newspaper:',
  '  working_title: "x - 1 OUD"',
  '  planning_date: 2026-10-07',
  '---',
})
assert(txt2:find('working_title: "x %- 1 LEUGENBANKIEN 2026%-10%-07"'),
  'datum-only ontbreekt: ' .. txt2)

-- Geen metadata-stap (geen planning_date) → werktitel onveranderd.
local txt3 = apply_with_fm({ '---', 'newspaper:', '  working_title: "x - 1 OUD"', '---' })
assert(txt3:find('working_title: "x %- 1 LEUGENBANKIEN"'),
  'kale werktitel hoort ongewijzigd te blijven: ' .. txt3)
assert(not txt3:find('working_title: "x %- 1 LEUGENBANKIEN %d'),
  'zonder metadata-stap mag er geen datum bij: ' .. txt3)

print('rubriek disambiguator: OK')
