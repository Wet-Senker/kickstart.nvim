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
local original_open = vim.ui.open
vim.ui.open = function(url)
  opened_url = url
  return {}
end
assert(ai_text._open_published_url("https://example.test/article"), "browseropen gaf geen succes terug")
vim.ui.open = original_open
assert(opened_url == "https://example.test/article", "gepubliceerde URL ging niet naar de standaardbrowser")

print("publication status: OK")
