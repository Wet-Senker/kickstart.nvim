-- Headless test: agenda-modelezer en reject_calendar (<leader>aC).
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

print("calendar reject: OK")
