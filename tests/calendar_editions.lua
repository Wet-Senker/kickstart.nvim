local ai = require('ai_text')

local lines = {
  '---', 'calendar:', '  mode: multiple', '  calendar_ready: true', '  items:',
  '  - item_key: event-1', '    editions:', '    - B', '    - SW',
  '    calendar_ready: true', '    calendar_title: Koffiemoment',
  '    city: Kampen', '    calendar_body: Pleegouders vertellen.',
  '  - item_key: event-2', '    editions: null', '    calendar_ready: true',
  '    calendar_title: Dalfsen', '    city: Dalfsen',
  '  - item_key: event-3', '    editions: []', '    calendar_ready: true',
  '    calendar_title: Niet publiceren',
  '  - item_key: event-4', '    calendar_ready: true', '    calendar_title: Bestaand item',
  '---', '', 'e: K', '', '=== ARTIKEL ===', '', 'Hoofdtekst',
}
local before = vim.deepcopy(lines)
local result = table.concat(assert(ai._build_calendar_section_lines(lines)), '\n')
assert(result:find('Editie: B, SW\nTitel: Koffiemoment', 1, true), result)
assert(result:find('Editie: kiezen\nTitel: Dalfsen', 1, true), result)
assert(result:find('Editie: geen\nTitel: Niet publiceren', 1, true), result)
assert(select(2, result:gsub('Editie:', '')) == 3, 'legacy item must not be silently scoped')
assert(not result:find('Editie: K', 1, true), 'parent edition must not override event choices')
assert(vim.deep_equal(lines, before), 'presentation changed durable publication state')
assert(result:find('calendar-key: event-3', 1, true), 'excluded item must remain editable')
print('calendar editions: OK')
