local ai_text = require("ai_text")

local base = {
  "=== ARTIKEL ===",
  "",
  "Kop",
  "",
  "Artikeltekst.",
  "",
  "---",
  "",
  "## Kalender",
  "",
  "Titel: Open dag",
  "Datum: 2026-08-29",
}

local function rendered(lines)
  return table.concat(lines, "\n")
end

local function count_heading(lines, heading)
  local count = 0
  for _, line in ipairs(lines) do
    if line == heading then count = count + 1 end
  end
  return count
end

local linkedin_first = ai_text._upsert_tail_section(base, "LinkedIn", "LinkedIn-tekst.")
local linkedin_then_facebook = ai_text._upsert_tail_section(
  linkedin_first,
  "Facebook",
  "Facebooktekst."
)

local facebook_first = ai_text._upsert_tail_section(base, "Facebook", "Facebooktekst.")
local facebook_then_linkedin = ai_text._upsert_tail_section(
  facebook_first,
  "LinkedIn",
  "LinkedIn-tekst."
)

assert(
  rendered(linkedin_then_facebook) == rendered(facebook_then_linkedin),
  "socialsecties hangen af van welke AI-taak het eerst klaar is"
)

local combined = rendered(linkedin_then_facebook)
assert(combined:find("## Kalender", 1, true), "bestaande kalendersectie verdween")
assert(combined:find("Titel: Open dag", 1, true), "kalenderinhoud verdween")
assert(
  combined:find("## Facebook", 1, true) < combined:find("## LinkedIn", 1, true),
  "Facebook hoort vóór LinkedIn te staan"
)

local replaced = ai_text._upsert_tail_section(
  linkedin_then_facebook,
  "Facebook",
  "Nieuwe Facebooktekst."
)
assert(count_heading(replaced, "## Facebook") == 1, "Facebooksectie werd dubbel toegevoegd")
assert(count_heading(replaced, "## LinkedIn") == 1, "LinkedInsectie verdween of werd dubbel")
assert(rendered(replaced):find("Nieuwe Facebooktekst.", 1, true), "Facebooktekst niet vervangen")
assert(rendered(replaced):find("LinkedIn-tekst.", 1, true), "LinkedIntekst werd overschreven")

local empty_linkedin = ai_text._upsert_tail_section(base, "LinkedIn", "")
assert(count_heading(empty_linkedin, "## LinkedIn") == 1, "lege handmatige LinkedInsectie ontbreekt")

print("social sections: OK")
