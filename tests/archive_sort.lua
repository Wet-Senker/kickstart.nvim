-- Headless test: het archief sorteert .md's nieuwste-bestand-eerst (mtime).
-- Draai met:  nvim --headless -l tests/archive_sort.lua

package.loaded["pubble_archive"] = nil
local M = dofile(vim.fn.expand("~/.config/nvim/lua/pubble_archive.lua"))

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/2026/07/Historisch", "p")

local function touch(rel, mtime)
  local p = tmp .. "/" .. rel
  vim.fn.writefile({ "inhoud" }, p)
  vim.uv.fs_utime(p, mtime, mtime)
end

-- Bewust namen die op naam-sortering de verkeerde volgorde zouden geven,
-- maar op mtime juist: oudste naam = nieuwste bestand.
touch("2026/07/20260701 Oud bericht.md", 1000)
touch("2026/07/Historisch/verzenden-9999.md", 2000)
touch("2026/07/20260724 Nieuw bericht.md", 3000)

local files = M._archive_markdown_files(tmp)
assert(#files == 3, "verwacht 3 bestanden, kreeg " .. #files)
assert(files[1]:match("20260724 Nieuw"), "nieuwste (mtime 3000) hoort bovenaan")
assert(files[2]:match("verzenden%-9999"), "middelste (mtime 2000) als tweede")
assert(files[3]:match("20260701 Oud"), "oudste (mtime 1000) onderaan")

vim.fn.delete(tmp, "rf")
print("archive sort: OK")
