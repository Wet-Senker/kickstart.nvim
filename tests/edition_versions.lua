local ai = require("ai_text")
local review = ai._edition_review

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

local source_text = table.concat({
  "e: B, SW, ST",
  "",
  "=== ARTIKEL ===",
  "",
  "Gezamenlijke kop",
  "",
  "**OVERIJSSEL - Gezamenlijke intro.**",
  "",
  "Gezamenlijke body.",
}, "\n")

local state = {
  variants = {},
  names = {},
  statuses = {},
}

local function workspace()
  local variants = {}
  local ready = true
  for _, code in ipairs({ "B", "SW", "ST" }) do
    local status = state.statuses[code] or "review"
    if status ~= "approved" then ready = false end
    table.insert(variants, {
      code = code,
      name = state.names[code] or code,
      content = state.variants[code],
      status = status,
      content_sha256 = code .. "-hash",
      approved_sha256 = status == "approved" and (code .. "-hash") or vim.NIL,
    })
  end
  return {
    schema_version = 2,
    source_stale = false,
    ready = ready,
    variants = variants,
  }
end

local function rendered_markdown()
  local lines = {
    source_text,
    "",
    "---",
    "",
    "## Editieversies",
    "",
    "<!-- texttools-edition-workspace: 2 -->",
    "<!-- source-sha256: test -->",
  }
  for _, code in ipairs({ "B", "SW", "ST" }) do
    table.insert(lines, "")
    table.insert(lines, "### Editieversie " .. code .. " — " .. state.names[code])
    table.insert(lines, "<!-- approved-sha256: "
      .. (state.statuses[code] == "approved" and (code .. "-hash") or "-") .. " -->")
    table.insert(lines, "")
    table.insert(lines, state.variants[code])
  end
  table.insert(lines, "")
  table.insert(lines, "## Facebook")
  table.insert(lines, "")
  table.insert(lines, "Facebooktekst.")
  return table.concat(lines, "\n")
end

review._runner = function(_, action, payload, done)
  if action == "create" then
    for index, code in ipairs(payload.editions) do
      state.variants[code] = payload.variants[code]
      state.names[code] = payload.names[code] or code
      state.statuses[code] = "review"
    end
  elseif action == "update" then
    state.variants[payload.edition] = payload.content
    state.statuses[payload.edition] = payload.approve and "approved" or "review"
  elseif action ~= "status" then
    done(false, nil, "onverwachte testactie")
    return
  end
  done(true, {
    contract_version = 1,
    markdown = rendered_markdown(),
    workspace = workspace(),
  }, nil)
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(source_text .. "\n\n---\n\n## Facebook\n\nFacebooktekst.", "\n"))

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
assert(rendered:find("Gezamenlijke kop", 1, true), "gedeelde brontekst werd vervangen")
assert(rendered:find("### Editieversie B — De Brug", 1, true), "B-versie ontbreekt")
assert(rendered:find("### Editieversie SW — De Swollenaer", 1, true), "SW-versie ontbreekt")
assert(rendered:find("### Editieversie ST — De Stadskoerier", 1, true), "ST-versie ontbreekt")
assert(not rendered:find("Primaire versie hierboven", 1, true), "eerste versie bleef kunstmatig primair")
assert(rendered:find("## Facebook", 1, true), "bestaande beschermde sectie ging verloren")

local entries = review._review_buffers[buf]
assert(entries and entries.B and entries.SW and entries.ST, "niet iedere editie kreeg een buffer")
assert(text(entries.B):find("B kop", 1, true), "B-buffer heeft verkeerde inhoud")
assert(text(entries.SW):find("SW kop", 1, true), "SW-buffer heeft verkeerde inhoud")
assert(vim.bo[entries.B].buftype == "acwrite", "reviewbuffer is niet schrijfbaar gekoppeld")

local approved = false
review.sync(entries.B, true, function(ok) approved = ok end)
assert(approved, "B-versie kon niet worden goedgekeurd")
assert(vim.b[entries.B].edition_variant.status == "approved", "B-status bleef controleren")

vim.api.nvim_buf_set_lines(entries.SW, 0, -1, false, {
  "Nieuwe SW kop",
  "",
  "**ZWOLLE - Nieuwe intro.**",
  "",
  "Nieuwe body.",
})
local synced = false
review.sync(entries.SW, false, function(ok) synced = ok end)
assert(synced, "bewerkte SW-versie werd niet teruggeschreven")
assert(text(buf):find("Nieuwe SW kop", 1, true), "SW-edit kwam niet in de bronwerkruimte")
assert(vim.b[entries.SW].edition_variant.status == "review", "edit werd stil goedgekeurd")

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

local race_source = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(race_source, 0, -1, false, {
  "e: B, SW",
  "",
  "=== ARTIKEL ===",
  "",
  "Gezamenlijk artikel",
  "",
  "## Facebook",
  "",
  "Facebooktekst.",
})
local race_attempts = 0
review._runner = function(source_buf, action, payload, done)
  assert(action == "create", "onverwachte actie in race-test")
  race_attempts = race_attempts + 1
  if race_attempts == 1 then
    vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "Achtergrondwijziging." })
  end
  done(true, {
    contract_version = 1,
    markdown = payload.markdown,
    workspace = {
      schema_version = 2,
      source_stale = false,
      ready = false,
      variants = {
        { code = "B", name = "De Brug", content = payload.variants.B, status = "review" },
        { code = "SW", name = "De Swollenaer", content = payload.variants.SW, status = "review" },
      },
    },
  }, nil)
end
local race_done = false
review.create_workspace(
  race_source,
  "Gezamenlijk artikel",
  { "B", "SW" },
  { "De Brug", "De Swollenaer" },
  {
    B = "Brugkop\n\n**KAMPEN - Intro.**\n\nBody.",
    SW = "Zwollekop\n\n**ZWOLLE - Intro.**\n\nBody.",
  },
  function(ok) race_done = ok end
)
assert(race_done, "werkruimte faalde na veilige retry")
assert(race_attempts == 2, "late bronwijziging leidde niet tot exact één retry")
assert(
  text(race_source):find("Achtergrondwijziging.", 1, true),
  "achtergrondwijziging werd door laat resultaat overschreven"
)
review.close(race_source, true)

ai._edition_versions_confirm = original_confirm
ai._edition_variant_runner = original_runner
review._runner = nil

print("edition versions: OK")
