-- Headless test: agenda-modelezer, impliciet weigeren na verwijderen en
-- de laatste kalendercontrole bij verzenden.
-- Draai met:  nvim --headless -l tests/calendar_reject.lua

local ai = require("ai_text")

local function eq(got, want, label)
  if got ~= want then
    error(("%s: kreeg %q verwacht %q"):format(label, tostring(got), tostring(want)))
  end
end

-- 1. _agenda_mode_from_lines: drie standen + aliassen.
eq(ai._agenda_mode_from_lines({ "agenda: nee", "", "Tekst" }), "off", "nee")
eq(ai._agenda_mode_from_lines({ "agenda: f", "", "Tekst" }), "off", "f")
eq(ai._agenda_mode_from_lines({ "agenda: ja", "", "Tekst" }), "on", "ja")
eq(ai._agenda_mode_from_lines({ "cal: x", "", "Tekst" }), "on", "cal x")
eq(ai._agenda_mode_from_lines({ "calendar: x", "", "Tekst" }), "on", "calendar x")
eq(ai._agenda_mode_from_lines({ "agenda: auto", "", "Tekst" }), "auto", "auto")
eq(ai._agenda_mode_from_lines({ "Gewone tekst" }), "auto", "geen code")

-- 2. reject_calendar: sectie weg, cache gewist, agenda: nee bovenaan.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "Kop", "", "KAMPEN - Tekst.", "", "---", "", "## Kalender", "", "Datum: 2026-09-08",
})
vim.b[buf].cached_calendar_metadata = { "x" }
ai.reject_calendar(buf)

local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
eq(out[1], "agenda: nee", "agenda: nee bovenaan")
if table.concat(out, "\n"):find("## Kalender") then error("## Kalender-sectie niet verwijderd") end
eq(vim.b[buf].cached_calendar_metadata, nil, "cache gewist")
eq(vim.b[buf].calendar_ai_started, true, "ai_started gezet")

-- Een volgende sectie blijft staan als alleen Kalender wordt geweigerd.
local with_facebook = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(with_facebook, 0, -1, false, {
  "=== ARTIKEL ===", "", "Kop", "", "Tekst.", "", "---", "",
  "## Kalender", "", "Datum: 2026-09-08", "", "## Facebook", "", "Bericht.",
})
ai.reject_calendar(with_facebook)
local facebook_text = table.concat(vim.api.nvim_buf_get_lines(with_facebook, 0, -1, false), "\n")
assert(not facebook_text:find("## Kalender", 1, true), "Kalender bleef vóór Facebook staan")
assert(facebook_text:find("## Facebook", 1, true), "Facebook verdween met Kalender")

-- 3. Idempotent: nogmaals weigeren geeft geen tweede regel.
ai.reject_calendar(buf)
local count = 0
for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
  if vim.trim(l) == "agenda: nee" then count = count + 1 end
end
eq(count, 1, "precies één agenda: nee")

-- 4. Bestaande 'agenda: ja' wordt vervangen door de weigering.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "agenda: ja", "", "Kop", "", "Tekst." })
ai.reject_calendar(buf2)
local out2 = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
eq(out2[1], "agenda: nee", "ja vervangen door nee")
for _, l in ipairs(out2) do
  if vim.trim(l) == "agenda: ja" then error("oude agenda: ja bleef staan") end
end

-- 5. Een zichtbaar kalenderblok wordt onthouden. Verwijdert de redacteur het
-- daarna, dan wordt dat vóór verzending zonder extra vraag `agenda: nee`.
local removed = vim.api.nvim_create_buf(false, true)
local article = {
  "=== ARTIKEL ===", "", "Concert in de kerk", "",
  "Op zaterdag 26 september 2026 begint om 20.00 uur een concert. Bezoekers zijn welkom en kaarten zijn verkrijgbaar.",
}
local with_calendar = vim.deepcopy(article)
vim.list_extend(with_calendar, { "", "---", "", "## Kalender", "", "Datum: 2026-09-26" })
vim.api.nvim_buf_set_lines(removed, 0, -1, false, with_calendar)
eq(ai._calendar_decision_before_send(removed), "continue", "zichtbaar blok")
eq(vim.b[removed].calendar_section_seen, true, "zichtbaar blok onthouden")
local removed_block = vim.deepcopy(article)
vim.list_extend(removed_block, { "", "---", "" })
vim.api.nvim_buf_set_lines(removed, 0, -1, false, removed_block)
vim.b[removed].cached_calendar_metadata = { "oude kalendercache" }
local original_send_confirm = ai._calendar_send_confirm
ai._calendar_send_confirm = function() error("verwijderd blok vroeg opnieuw om bevestiging") end
eq(ai._calendar_decision_before_send(removed), "continue", "verwijderd blok")
ai._calendar_send_confirm = original_send_confirm
eq(vim.b[removed].cached_calendar_metadata, nil, "cache na verwijderen gewist")
eq(vim.api.nvim_buf_get_lines(removed, 0, 1, false)[1], "agenda: nee", "verwijderen werd weigering")
assert(
  not table.concat(vim.api.nvim_buf_get_lines(removed, 0, -1, false), "\n"):match("%-%-%-%s*$"),
  "lege sectiescheiding bleef na verwijderen staan"
)

-- 6. Was er nog nooit een kalenderblok, dan vraagt een sterke kandidaat bij
-- verzenden alsnog. Ja bereidt eerst zichtbaar voor; nee onthoudt de weigering.
local late_yes = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(late_yes, 0, -1, false, article)
local asked_score
ai._calendar_send_confirm = function(score)
  asked_score = score
  return 1
end
eq(ai._calendar_decision_before_send(late_yes), "generate", "late ja")
assert(asked_score and asked_score >= 8, "late kalenderkandidaat kreeg geen vraag")

local late_no = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(late_no, 0, -1, false, article)
ai._calendar_send_confirm = function() return 2 end
eq(ai._calendar_decision_before_send(late_no), "continue", "late nee")
eq(vim.api.nvim_buf_get_lines(late_no, 0, 1, false)[1], "agenda: nee", "late nee niet onthouden")

local late_cancel = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(late_cancel, 0, -1, false, article)
ai._calendar_send_confirm = function() return 0 end
eq(ai._calendar_decision_before_send(late_cancel), "cancel", "late annuleren")
assert(
  vim.api.nvim_buf_get_lines(late_cancel, 0, 1, false)[1] ~= "agenda: nee",
  "annuleren werd als weigering opgeslagen"
)
ai._calendar_send_confirm = original_send_confirm

-- 7. De aparte hoofdletter-C-leader is vervallen; verwijderen is de bediening.
eq(vim.fn.maparg("<leader>aC", "n"), "", "oude aC-mapping")

print("calendar reject: OK")
