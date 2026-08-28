local ai_text = require("ai_text")
local recognition = require("article_recognition")

local threshold = 8

local kunstweekend = [[
Kunstweekend in de oude fabriek

Van zaterdag 26 september tot en met zondag 27 september 2026 wordt in De
Oude Fabriek aan de Havenweg 4 in Kampen een kunstweekend gehouden. Het
programma begint beide dagen om 10.00 uur. Bezoekers kunnen werk bekijken van
regionale kunstenaars en demonstraties bijwonen.
]]

local wegafsluiting = [[
Van zaterdag 26 september tot en met zondag 27 september 2026 is de Havenweg
afgesloten. De afsluiting begint om 10.00 uur. Verkeer wordt omgeleid.
]]

local gewone_vergadering = [[
De raad besprak op zaterdag 26 september 2026 de begroting. De vergadering
begon om 10.00 uur en was niet toegankelijk voor publiek.
]]

local wekelijkse_lessen = [[
De Kunstloods verzorgt van maandag 31 augustus tot en met vrijdag 2 oktober
2026 iedere maandag, dinsdag, woensdag, donderdag en vrijdag kunstlessen.
De lessen beginnen dagelijks om 09.00 uur. Deelnemers werken aan tekenen,
schilderen en boetseren.
]]

assert(
  ai_text._calendar_signal_score(kunstweekend) >= threshold,
  "expliciet meerdaags kunstweekend werd niet als kalenderkandidaat herkend"
)
assert(
  ai_text._calendar_signal_score(wegafsluiting) < threshold,
  "meerdaagse wegafsluiting gaf een kalender-false-positive"
)
assert(
  ai_text._calendar_signal_score(gewone_vergadering) < threshold,
  "nieuwsverslag met datum en tijd gaf een kalender-false-positive"
)
assert(
  ai_text._calendar_signal_score(wekelijkse_lessen) >= threshold,
  "herhalende lessen voor deelnemers werden niet als kalenderkandidaat herkend"
)

local veel_data = [[
maandag 24 augustus
dinsdag 25 augustus
woensdag 26 augustus
donderdag 27 augustus
Nogmaals op dinsdag 25 augustus.
]]
assert(
  recognition.calendar_date_count(veel_data) == 4,
  "afzonderlijke datums werden niet correct geteld of een herhaling telde dubbel"
)
assert(
  recognition.calendar_date_count("2026-08-24, 25/08/2026 en 26-08-2026") == 3,
  "numerieke datums werden niet correct geteld"
)

local incomplete_single = {
  "---",
  "calendar:",
  "  event_candidate: true",
  "  calendar_ready: false",
  "  event_title: Hanzefestival 2026",
  "  calendar_title: Hanzefestival Kampen",
  "  event_date: '2026-09-03'",
  "  event_end_date: '2026-09-05'",
  "  start_time: null",
  "  location_name: Binnenstad Kampen",
  "  city: Kampen",
  "  calendar_body: Drie dagen met muziek, kermis en maritiem erfgoed.",
  "  missing_event_fields:",
  "  - start_time",
  "  needs_manual_check: true",
  "  manual_check_reason: Begintijd ontbreekt.",
  "---",
}
local incomplete_section = ai_text._build_calendar_section_lines(incomplete_single)
assert(incomplete_section, "onvolledig enkel agenda-item werd volledig verborgen")
local incomplete_text = table.concat(incomplete_section, "\n")
assert(
  incomplete_text:find("Titel: Hanzefestival Kampen", 1, true),
  "bekende kalendervelden ontbreken in de controlesectie"
)
assert(
  incomplete_text:find("<!-- Ontbreekt: start_time -->", 1, true),
  "ontbrekende begintijd werd niet zichtbaar gemarkeerd"
)

local no_event = {
  "---",
  "calendar:",
  "  event_candidate: false",
  "  calendar_ready: false",
  "  missing_event_fields:",
  "---",
}
assert(
  ai_text._build_calendar_section_lines(no_event) == nil,
  "tekst zonder evenement kreeg toch een kalendersectie"
)

print("calendar detection: OK")
