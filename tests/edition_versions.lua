local ai = require("ai_text")

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "e: B, SW, ST",
  "",
  "=== ARTIKEL ===",
  "",
  "Gezamenlijke kop",
  "",
  "**OVERIJSSEL - Gezamenlijke intro.**",
  "",
  "Gezamenlijke body.",
  "",
  "---",
  "",
  "## Facebook",
  "",
  "Facebooktekst.",
})

local original_confirm = ai._edition_versions_confirm
local original_runner = ai._edition_variant_runner
ai._edition_versions_confirm = function() return 1 end
local requested = {}
ai._edition_variant_runner = function(_, code, _, done)
  table.insert(requested, code)
  done(
    true,
    code .. " kop\n\n**OVERIJSSEL - Intro voor " .. code .. ".**\n\nBody voor " .. code .. "."
  )
end

ai._offer_and_generate_edition_versions(
  buf,
  "Gezamenlijke kop\n\n**OVERIJSSEL - Gezamenlijke intro.**\n\nGezamenlijke body.",
  { "B", "SW", "ST" },
  { "De Brug", "De Swollenaer", "De Stadskoerier" }
)

local rendered = text(buf)
assert(table.concat(requested, ",") == "B,SW,ST", "niet iedere editie kreeg een eigen AI-call")
assert(rendered:find("B kop", 1, true), "primaire versie staat niet in de gewone artikelbody")
assert(rendered:find("## Editieversies", 1, true), "beschermd editieversieblok ontbreekt")
assert(rendered:find("Primaire versie hierboven: B — De Brug.", 1, true), "primaire editie is niet gelabeld")
assert(rendered:find("### Editieversie SW — De Swollenaer", 1, true), "SW-versie ontbreekt")
assert(rendered:find("### Editieversie ST — De Stadskoerier", 1, true), "ST-versie ontbreekt")
assert(rendered:find("## Facebook", 1, true), "bestaande beschermde sectie ging verloren")

local declined = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(declined, 0, -1, false, { "Gezamenlijk artikel" })
ai._edition_versions_confirm = function() return 2 end
local ran = false
ai._edition_variant_runner = function() ran = true end
ai._offer_and_generate_edition_versions(
  declined,
  "Gezamenlijk artikel",
  { "B", "SW" },
  { "De Brug", "De Swollenaer" }
)
assert(not ran, "AI-call startte ondanks keuze voor gezamenlijke versie")
assert(not text(declined):find("## Editieversies", 1, true), "bij weigeren ontstond toch een versieblok")

assert(
  ai._normalized_edition_variant("Kop\n\n**OVERIJSSEL - Intro.**\n\nBody."),
  "geldige krantversie werd geweigerd"
)
assert(
  not ai._normalized_edition_variant("Kop\n\n## Uitleg\n\nBody."),
  "sectieopmaak uit AI-uitvoer werd niet geweigerd"
)

ai._edition_versions_confirm = original_confirm
ai._edition_variant_runner = original_runner

print("edition versions: OK")
