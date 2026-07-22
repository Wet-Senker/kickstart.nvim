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

print("edition suggestions: OK")
