-- De verzending kan als typed resultaat "needs_print_timing" teruggeven wanneer
-- de krant een andere tijdsvorm nodig heeft en die nog niet is gemaakt. De
-- client moet die modus uit de PUBBLE_RESULT_JSON kunnen lezen, zodat hij de
-- buffer met de verrijkte metadata kan herladen en de keuze (kranttijdsversie /
-- alleen website) alsnog kan bieden i.p.v. een ruwe crash te tonen.
local ai = require('ai_text')

assert(type(ai._publication_status_from_output) == 'function',
  'de resultaatparser ontbreekt')

local stdout = table.concat({
  '[B] Voor de krant is een andere tijdsvorm nodig.',
  'PUBBLE_RESULT_JSON: {"mode":"needs_print_timing","outcome":"success",'
    .. '"editions":["B","SW"],"phases":[]}',
}, '\n')

local status = ai._publication_status_from_output(stdout, '')
assert(type(status) == 'table', 'resultaat kon niet worden geparsed')
assert(status.mode == 'needs_print_timing',
  'de kranttijd-keuzemodus werd niet herkend')
assert(type(status.editions) == 'table' and status.editions[1] == 'B'
  and status.editions[2] == 'SW', 'de betrokken edities ontbreken')

-- Een gewoon geslaagd resultaat mag deze modus juist niet dragen.
local ok_status = ai._publication_status_from_output(
  'PUBBLE_RESULT_JSON: {"mode":"published","outcome":"success","phases":[]}',
  ''
)
assert(ok_status and ok_status.mode == 'published',
  'een geslaagde plaatsing zou mode=published moeten geven')

print('print timing reentry: OK')
