local ai = require 'ai_text'
for _, multiple in ipairs { false, true } do
  local lines = { '---', 'calendar:', '  event_candidate: true', '  calendar_ready: false' }
  local indent = '  '
  if multiple then
    vim.list_extend(lines, { '  mode: multiple', '  items:', '  - item_key: event-1' })
    indent = '    '
  end
  vim.list_extend(lines, {
    indent .. 'event_candidate: true', indent .. 'calendar_ready: false',
    indent .. 'calendar_title: Bijeenkomst', indent .. "event_date: '2099-02-02'",
    indent .. 'recurrence: wekelijks', indent .. 'recurrence_days:', indent .. '- maandag',
    indent .. 'recurrence_until: null', indent .. 'recurrence_excluded_dates:',
    indent .. "- '2099-02-02'", indent .. 'recurrence_exclusions_note: niet tijdens schoolvakanties',
    indent .. 'schedule_mode: kiezen', indent .. 'missing_event_fields:',
    indent .. '- recurrence_until', indent .. '- recurrence_exclusions_note',
    indent .. "start_time: '09:30'", indent .. 'location_name: Buurthuis',
    indent .. 'city: Kampen', indent .. 'calendar_body: Een bijeenkomst.', '---',
  })
  local snapshot = vim.deepcopy(lines)
  local text = table.concat(assert(ai._build_calendar_section_lines(lines)), '\n')
  assert(text:find('Herhaling: wekelijks', 1, true))
  assert(text:find('Herhaal tot:\n', 1, true), 'ontbrekende einddatum heeft geen invulregel')
  assert(text:find('Dagen: maandag', 1, true))
  assert(text:find('Uitgesloten datums: 2099-02-02', 1, true), 'uitsluitingen verdwenen uit weergave')
  assert(text:find('Uitsluitingen controleren: niet tijdens schoolvakanties', 1, true))
  assert(text:find('Agendavorm: kiezen', 1, true))
  assert(not text:find('recurrence_until', 1, true), 'technische veldnaam bleef in uitleg staan')
  assert(vim.deep_equal(snapshot, lines), 'weergave veranderde bron/IDs')
  local message = ai._calendar_notice(lines)
  assert(message:find('Herhaal tot', 1, true) and message:find('Uitgesloten datums controleren', 1, true))
end
print 'calendar schedule: OK'
