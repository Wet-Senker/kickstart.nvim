local ai = require("ai_text")

for _, multiple in ipairs({ false, true }) do
  for _, date_key in ipairs({ "date", "event_date" }) do
    local lines = { "---", "calendar:", "  event_candidate: true", "  calendar_ready: false" }
    local indent = "  "
    if multiple then
      vim.list_extend(lines, { "  mode: multiple", "  items:", "  - item_key: event-1" })
      indent = "    "
    end
    vim.list_extend(lines, {
      indent .. "calendar_ready: false",
      indent .. "calendar_title: null",
      indent .. "event_date: null",
      indent .. "start_time: null",
      indent .. "location_name: null",
      indent .. "city: null",
      indent .. "missing_event_fields:",
      indent .. "- calendar_title",
      indent .. "- " .. date_key,
      indent .. "- start_time",
      indent .. "- location_name",
      indent .. "- city",
      indent .. "calendar_body: Een optreden voor iedereen.",
      "---",
    })
    local before = vim.deepcopy(lines)
    local section = assert(ai._build_calendar_section_lines(lines))
    local text = table.concat(section, "\n")
    for _, label in ipairs({ "Titel", "Datum", "Tijd", "Locatie", "Stad" }) do
      local count = 0
      for _, line in ipairs(section) do
        if line == label .. ":" then count = count + 1 end
      end
      assert(count == 1, "ontbrekend veld niet precies eenmaal invulbaar: " .. label .. "\n" .. text)
    end
    assert(text:find("Datum: YYYY-MM-DD", 1, true), "datumformaat ontbreekt voor " .. date_key)
    assert(text:find("Datum: 2026-09-03", 1, true), "datumvoorbeeld ontbreekt")
    assert(text:find("Tijd: HH:MM", 1, true), "tijdformaat ontbreekt")
    assert(text:find("\nEen optreden voor iedereen.", 1, true), "agendatekst verdwenen")
    for _, label in ipairs({ "Einddatum", "Eindtijd", "Herhaling", "Adres" }) do
      assert(not text:find("\n" .. label .. ":", 1, true), "optioneel leeg veld toegevoegd: " .. label)
    end
    assert(vim.deep_equal(lines, before), "renderer veranderde de bron")
  end
end

local complete = table.concat(assert(ai._build_calendar_section_lines({
  "---", "calendar:", "  event_candidate: true", "  calendar_ready: true",
  "  calendar_title: Concert", "  event_date: '2026-10-17'", "  start_time: '10:00'",
  "  location_name: Bovenkerk", "  city: Kampen", "  calendar_body: Muziek.", "---",
})), "\n")
assert(complete:find("Datum: 2026-10-17\nTijd: 10:00\nLocatie: Bovenkerk", 1, true),
  "bekende velden zijn veranderd")
assert(not complete:find("<!-- Ontbreekt:", 1, true), "compleet item kreeg ontbreektmelding")
print("calendar missing fields: OK")
