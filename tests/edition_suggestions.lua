local ai_text = require("ai_text")

local lines = ai_text._edition_control_lines({
  editions = { "SW" },
  suggestions = {
    { editions = { "B" } },
    { editions = { "B", "ST" } },
  },
  suggestion_reasons = {
    {
      edition = "B",
      reasons = { "eigen koppeling ‘Hedon’", "plaatsnaam ‘Kampen’" },
    },
    {
      edition = "ST",
      reasons = { "eigen koppeling ‘Meerpaaldagen’" },
    },
    {
      edition = "SW",
      reasons = { "reeds gekozen en dus niet tonen" },
    },
  },
})

assert(
  lines[1] == "e: SW, SUGGESTIE, B, ST",
  "de snelle SUGGESTIE-acceptatieregel veranderde"
)
assert(
  lines[2] == "suggestiereden: B — eigen koppeling ‘Hedon’, plaatsnaam ‘Kampen’; "
    .. "ST — eigen koppeling ‘Meerpaaldagen’",
  "suggestieredenen zijn niet per voorgestelde editie opgebouwd"
)
assert(#lines == 2, "onverwachte extra controleregels")

local accepted = ai_text._edition_control_lines({
  editions = { "SW", "B" },
  suggestions = {},
  suggestion_reasons = {
    { edition = "B", reasons = { "mag niet terugkomen na acceptatie" } },
  },
})
assert(accepted[1] == "e: SW, B", "geaccepteerde editie bleef een suggestie")
assert(#accepted == 1, "redenregel bleef staan nadat de suggestie was geaccepteerd")

assert(ai_text._is_control_key("koppel"), "koppel: wordt niet als controleregel herkend")
assert(ai_text._is_control_key("ontkoppel"), "ontkoppel: wordt niet als controleregel herkend")
assert(
  ai_text._is_control_key("suggestiereden"),
  "suggestiereden: wordt niet als controleregel herkend"
)

-- Onzekere import (geen expliciete e:, detectie confidence "none"): niets
-- gekozen, alle herkende plaatsen als suggestie, met reden per editie.
local uncertain = ai_text._edition_control_lines({
  editions = { "B" }, -- fallback; mag niet als keuze verschijnen
  has_explicit_editions = false,
  detection = { confidence = "none" },
  places = {
    { place = "Dronten", editions = { "D" }, kind = "place" },
    { place = "Kampen", editions = { "B" }, kind = "place" },
    { place = "Zwolle", editions = { "SW" }, kind = "place" },
  },
})
assert(
  uncertain[1] == "e: SUGGESTIE, D, B, SW",
  "onzekere import koos toch een editie: " .. tostring(uncertain[1])
)
assert(
  uncertain[2]
    == "suggestiereden: D — plaatsnaam ‘Dronten’; B — plaatsnaam ‘Kampen’; "
      .. "SW — plaatsnaam ‘Zwolle’",
  "onzekere redenregel klopt niet: " .. tostring(uncertain[2])
)

-- Gekozen krant krijgt nu óók een reden (uit source), naast de suggestie.
local chosen_reason = ai_text._edition_control_lines({
  editions = { "B" },
  has_explicit_editions = false,
  detection = { confidence = "high" },
  source = "dateline KAMPEN",
  suggestions = { { editions = { "SW" } } },
  suggestion_reasons = { { edition = "SW", reasons = { "plaatsnaam ‘Zwolle’" } } },
})
assert(
  chosen_reason[1] == "e: B, SUGGESTIE, SW",
  "gekozen+suggestie e-regel klopt niet: " .. tostring(chosen_reason[1])
)
assert(
  chosen_reason[2] == "suggestiereden: B — dateline KAMPEN; SW — plaatsnaam ‘Zwolle’",
  "reden voor gekozen krant ontbreekt: " .. tostring(chosen_reason[2])
)

print("edition suggestions: OK")
