local test_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ":h:h")
vim.opt.runtimepath:prepend(repo_root)

local test_root = vim.fn.tempname()
vim.fn.mkdir(test_root .. "/inbox/werk", "p")
vim.env.TEXTTOOLS_INBOX_DIR = test_root .. "/inbox"

package.loaded.texttools_paths = nil
package.loaded.ai_text = nil
local paths = require("texttools_paths")
local ai = require("ai_text")

assert(paths.work() == test_root .. "/inbox/werk", "de pv-werkmap volgt TEXTTOOLS_INBOX_DIR niet")
assert(
  vim.tbl_contains(ai._import_patterns, paths.work() .. "/*.md"),
  "de werkmap activeert de importherkenning niet"
)
assert(
  vim.tbl_contains(ai._import_patterns, vim.fn.expand("~/Desktop") .. "/*.md"),
  "Desktopcompatibiliteit voor bestaande imports ontbreekt"
)
assert(
  ai._is_managed_import_path(paths.inbox() .. "/herstel.md"),
  "een direct transactioneel Inboxbestand is geen beheerde hervatbron"
)

local source = paths.work() .. "/testartikel.md"
vim.fn.writefile({ "Testkop", "", "KAMPEN - Testtekst." }, source)
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, source)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(source))

local ok, err, managed = ai._finalize_published_buffer(
  buf,
  source,
  { "**Verstuurd naar Pubble op 28-08-2026 12:00**", "https://example.test/artikel" },
  test_root .. "/archief/artikel.md"
)
assert(ok and err == nil and managed, "een beheerd werkbestand werd niet afgerond")
assert(vim.fn.filereadable(source) == 0, "het afgeronde werkbestand bleef op schijf staan")
assert(vim.bo[buf].buftype == "nofile", "de nacontrolebuffer bleef schrijfbaar")
assert(vim.bo[buf].modifiable == false, "de nacontrolebuffer bleef aanpasbaar")
assert(vim.bo[buf].readonly == true, "de nacontrolebuffer is niet alleen-lezen")
assert(vim.bo[buf].modified == false, "de nacontrolebuffer vraagt nog om opslaan")
assert(
  vim.api.nvim_buf_get_name(buf):match("^pubble%-nacontrole://"),
  "de nacontrolebuffer bleef aan het verwijderde werkpad gekoppeld"
)
local write_ok = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd("write") end)
assert(not write_ok, ":w kon het verwijderde werkbestand opnieuw aanmaken")

local failed_source = paths.work() .. "/kan-niet-weg.md"
vim.fn.writefile({ "Test" }, failed_source)
local failed_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(failed_buf, failed_source)
vim.api.nvim_buf_set_lines(failed_buf, 0, -1, false, { "Test" })
local original_delete = ai._delete_source_file
ai._delete_source_file = function() return -1 end
local cleanup_ok, cleanup_error, cleanup_managed = ai._finalize_published_buffer(
  failed_buf,
  failed_source,
  { "**Verstuurd naar Pubble op 28-08-2026 12:00**" },
  test_root .. "/archief/test.md"
)
ai._delete_source_file = original_delete
assert(not cleanup_ok and cleanup_managed, "een verwijderfout werd niet gemeld")
assert(cleanup_error:find(failed_source, 1, true), "de verwijderfout noemt het werkbestand niet")
assert(vim.fn.filereadable(failed_source) == 1, "de verwijderfouttest verloor onverwacht de bron")
assert(vim.bo[failed_buf].buftype == "nofile", "een mislukte cleanup bleef opnieuw opslagbaar")

local external = test_root .. "/eigen-artikel.md"
vim.fn.writefile({ "Eigen tekst" }, external)
local external_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(external_buf, external)
vim.api.nvim_buf_set_lines(external_buf, 0, -1, false, { "Eigen tekst" })
local external_ok, _, external_managed = ai._finalize_published_buffer(
  external_buf,
  external,
  { "**Verstuurd naar Pubble op 28-08-2026 12:00**" },
  test_root .. "/archief/eigen.md"
)
assert(external_ok and not external_managed, "een extern bestand werd als pv-bron behandeld")
assert(vim.fn.filereadable(external) == 1, "een willekeurig extern Markdownbestand is verwijderd")
assert(vim.bo[external_buf].buftype == "", "een extern bestand werd een nofile-buffer")

vim.fn.delete(test_root, "rf")
print("published review buffer: OK")
