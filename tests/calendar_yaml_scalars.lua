local ai = require("ai_text")

local cases = {
  { "'''t Kroegje'", "'t Kroegje" },
  { "'''t Ukien'", "'t Ukien" },
  { "'Café d''Artagnan'", "Café d'Artagnan" },
  { "'Letterlijk twee '''' apostrofs'", "Letterlijk twee '' apostrofs" },
  { "'t Kroegje", "'t Kroegje" },
  { '"\'t Ukien"', "'t Ukien" },
  { '"Café \\"De Reeve\\""', 'Café "De Reeve"' },
  { '"Caf\\xE9"', "Café" },
  { '"Caf\\u00E9"', "Café" },
  { '"Muziek \\U0001F3B5"', "Muziek 🎵" },
  { '"Pad C:\\\\foto"', "Pad C:\\foto" },
}

for _, multiple in ipairs({ false, true }) do
  for _, case in ipairs(cases) do
    local lines = { "---", "calendar:", "  event_candidate: true", "  calendar_ready: true" }
    local indent = "  "
    if multiple then
      vim.list_extend(lines, { "  mode: multiple", "  items:", "  - item_key: event-1" })
      indent = "    "
    end
    vim.list_extend(lines, {
      indent .. "calendar_ready: true",
      indent .. "calendar_title: " .. case[1],
      indent .. "event_date: '2026-10-18'",
      indent .. "start_time: '17:00'",
      indent .. "location_name: " .. case[1],
      indent .. "city: Kampen",
      indent .. "calendar_body: " .. case[1],
      "---", "Artikelkop", "Artikeltekst met 't Kroegje en '' letterlijk.",
    })
    local before = vim.deepcopy(lines)
    local text = table.concat(assert(ai._build_calendar_section_lines(lines)), "\n")
    assert(text:find("Locatie: " .. case[2], 1, true), "verkeerde YAML-locatie: " .. case[1] .. "\n" .. text)
    assert(text:find("Titel: " .. case[2], 1, true), "verkeerde YAML-titel: " .. case[1])
    assert(text:find("\n" .. case[2], 1, true), "verkeerde YAML-body: " .. case[1])
    assert(vim.deep_equal(lines, before), "weergave heeft de bron gewijzigd")
  end
end

local warning = table.concat(ai._build_calendar_section_lines({
  "---", "calendar:", "  event_candidate: true", "  calendar_ready: true",
  "  needs_manual_check: true",
  "  manual_check_reason: Agenda-reeks niet volledig gecontroleerd.",
  "  calendar_title: Literair Café", "  event_date: '2026-10-18'",
  "  start_time: '17:00'", "  location_name: '''t Kroegje'", "  city: Kampen",
  "  calendar_body: Eerste bijeenkomst.", "---",
}), "\n")
assert(warning:find("<!-- Controle nodig: Agenda-reeks niet volledig gecontroleerd. -->", 1, true),
  "Python-reekswaarschuwing is niet zichtbaar in de kalenderreview")
print("calendar YAML scalars: OK")
