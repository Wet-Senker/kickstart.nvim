-- Headless test: prepare_article plaatst de === ARTIKEL ===-grens correct.
-- Draai met:  nvim --headless -l tests/prepare_article.lua

local ai = require("ai_text")

-- Zonder grens: prepare moet '=== ARTIKEL ===' bovenaan zetten (synchroon,
-- vóór de async editie-/metadata-stappen).
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "Kop van mijn eigen artikel",
  "",
  "KAMPEN - Ik heb dit zelf getikt en wil het online.",
})
ai.prepare_article(buf)
local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(vim.trim(out[1]) == "=== ARTIKEL ===", "grens moet bovenaan, kreeg: " .. tostring(out[1]))
-- Body moet behouden blijven onder de grens.
assert(table.concat(out, "\n"):find("KAMPEN %- Ik heb dit zelf getikt"), "body verdwenen")

-- Met bestaande grens: prepare mag geen tweede grens toevoegen.
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, {
  "editie: B",
  "=== ARTIKEL ===",
  "",
  "KAMPEN - Al voorbereid.",
})
ai.prepare_article(buf2)
local out2 = vim.api.nvim_buf_get_lines(buf2, 0, -1, false)
local count = 0
for _, l in ipairs(out2) do if vim.trim(l) == "=== ARTIKEL ===" then count = count + 1 end end
assert(count == 1, "precies één grens, kreeg " .. count)

print("prepare_article grens: OK")
