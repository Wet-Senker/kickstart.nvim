local ai_text = require("ai_text")

local partial = ai_text._publication_status_from_output(
  [[
Pubble article: https://example.test/303
PUBBLE_RESULT_JSON: {"mode":"published","outcome":"partial","phases":[{"name":"newspaper","status":"succeeded","detail":"ok","blocking":false},{"name":"web","status":"succeeded","detail":"ok","blocking":false},{"name":"teams","status":"failed","detail":"webhook stuk","blocking":false}]}
]],
  ""
)
assert(partial and partial.outcome == "partial", "partial-successstatus niet gelezen")
local partial_labels = ai_text._failed_publication_labels(partial)
assert(#partial_labels == 1 and partial_labels[1] == "Teams", "Teams-fase niet vertaald")

local failed = ai_text._publication_status_from_output(
  "",
  [[
Socialteksten zijn niet opgeslagen.
PUBBLE_RESULT_JSON: {"mode":"failed","outcome":"failed","phases":[{"name":"newspaper","status":"succeeded","detail":"ok","blocking":false},{"name":"web","status":"succeeded","detail":"ok","blocking":false},{"name":"social","status":"failed","detail":"PUT stuk","blocking":true},{"name":"teams","status":"skipped","detail":"niet uitgevoerd","blocking":false}]}
]]
)
assert(failed and failed.outcome == "failed", "blokkerende fasestatus niet gelezen")
local failed_labels = ai_text._failed_publication_labels(failed)
assert(
  #failed_labels == 1 and failed_labels[1] == "Facebook/LinkedIn",
  "socialfase niet begrijpelijk vertaald"
)

assert(
  ai_text._publication_status_from_output("gewone uitvoer", "fout") == nil,
  "uitvoer zonder resultaatmarker werd als status gezien"
)

local opened_url
local opened_command
local opened_options
local original_open = vim.ui.open
local original_system = vim.system
vim.ui.open = function(url)
  opened_url = url
  return {}
end
vim.system = function(command, options)
  opened_command = command
  opened_options = options
  return {}
end
assert(
  ai_text._open_published_url("https://example.test/article", true),
  "macOS-browseropen gaf geen succes terug"
)
assert(opened_url == nil, "macOS-browseropen gebruikte de focusnemende vim.ui.open-route")
assert(opened_command[1] == "/usr/bin/open", "macOS-browseropen gebruikte niet het systeemcommando")
assert(opened_command[2] == "-g", "macOS-browseropen miste de achtergrondoptie -g")
assert(
  opened_command[3] == "https://example.test/article",
  "gepubliceerde URL ontbrak in de achtergrondopdracht"
)
assert(opened_options.text == true, "macOS-browseropen startte zonder tekstoptie")

opened_command = nil
assert(
  ai_text._open_published_url("https://example.test/article", false),
  "niet-macOS-browseropen gaf geen succes terug"
)
vim.ui.open = original_open
vim.system = original_system
assert(opened_url == "https://example.test/article", "gepubliceerde URL ging niet naar de standaardbrowser")
assert(opened_command == nil, "niet-macOS-browseropen gebruikte onterecht het macOS-commando")

print("publication status: OK")
