local test_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ":h:h")
vim.opt.runtimepath:prepend(repo_root)

local test_root = vim.fn.tempname()
local real_inbox = test_root .. "/real-inbox"
local linked_inbox = test_root .. "/linked-inbox"
vim.fn.mkdir(real_inbox .. "/werk", "p")
vim.fn.system({ "ln", "-s", real_inbox, linked_inbox })
assert(vim.v.shell_error == 0, "testsymlink voor de Inbox kon niet worden gemaakt")
local canonical_inbox = vim.fn.resolve(real_inbox)
vim.env.TEXTTOOLS_INBOX_DIR = linked_inbox

package.loaded.texttools_paths = nil
package.loaded.ai_text = nil
local paths = require("texttools_paths")
local ai = require("ai_text")

assert(paths.work() == linked_inbox .. "/werk", "de pv-werkmap volgt TEXTTOOLS_INBOX_DIR niet")
assert(
  vim.tbl_contains(ai._import_patterns, paths.work() .. "/*.md"),
  "de werkmap activeert de importherkenning niet"
)
assert(
  vim.tbl_contains(ai._import_patterns, canonical_inbox .. "/werk/*.md"),
  "het echte pad achter de Inbox-symlink activeert de importherkenning niet"
)
assert(
  vim.tbl_contains(ai._import_patterns, vim.fn.expand("~/Desktop") .. "/*.md"),
  "Desktopcompatibiliteit voor bestaande imports ontbreekt"
)
assert(
  ai._is_managed_import_path(paths.inbox() .. "/herstel.md"),
  "een direct transactioneel Inboxbestand is geen beheerde hervatbron"
)

-- Regressie: `nvim --remote` kan de symlink vóór BufReadPost naar het echte
-- iCloud-pad oplossen. Ook dan moet exact dezelfde centrale importketen starten.
local resolved_import = canonical_inbox .. "/werk/via-echt-pad.md"
vim.fn.writefile({
  "=== ARTIKEL ===",
  "",
  "Concert",
  "",
  "KAMPEN - Zaterdag 19 september om 20.00 uur is er een concert voor publiek.",
}, resolved_import)
vim.cmd.edit(vim.fn.fnameescape(resolved_import))
assert(
  vim.b.send_import_body and vim.b.send_import_body ~= "",
  "BufReadPost sloeg een via de symlink opgelost werkbestand over"
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
local published_help = ai._article_context_help(buf)
assert(published_help.status:find('afgerond', 1, true), 'nacontrolebuffer mist afgeronde helpstatus')
assert(vim.inspect(published_help):find('Archief:', 1, true), 'nacontrolehulp mist archiefpad')

local running_buf = vim.api.nvim_create_buf(false, true)
vim.b[running_buf].publication_in_progress = true
assert(
  ai._article_context_help(running_buf).title == 'Publicatie wordt afgerond',
  'lopende publicatie kreeg geen dominante hulpstatus'
)

local recovery_file = test_root .. '/herstelstatus.md'
vim.fn.writefile({ 'bestaande ids' }, recovery_file)
local recovery_buf = vim.api.nvim_create_buf(false, true)
vim.b[recovery_buf].failed_send_file = recovery_file
local recovery_help = ai._article_context_help(recovery_buf)
assert(recovery_help.title == 'Publicatie veilig hervatten', 'herstelbuffer kreeg geen hervatadvies')
assert(vim.inspect(recovery_help):find('<leader>aw', 1, true), 'herstelhulp mist veilige hervatactie')

local review_buf = vim.api.nvim_create_buf(false, true)
vim.b[review_buf].publication_review_state = { editions = { 'B' } }
local publication_review_help = ai._article_context_help(review_buf)
assert(publication_review_help.title == 'Publicatieteksten controleren', 'eventreviewstatus ontbreekt')

local pending_buf = vim.api.nvim_create_buf(false, true)
require('buffer_jobs').start(pending_buf, 'Testtaak 1')
require('buffer_jobs').start(pending_buf, 'Testtaak 2')
vim.b[pending_buf].send_requested = true
local pending_help = ai._article_context_help(pending_buf)
assert(pending_help.status:find('Verzending staat klaar', 1, true), 'wachtende verzending ontbreekt in hulp')

local calendar_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(calendar_buf, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.', '', '## Kalender', '',
  '<!-- Ontbreekt: Tijd: HH:MM -->',
})
local calendar_help = ai._article_context_help(calendar_buf)
assert(calendar_help.title == 'Artikel met agenda-item', 'zichtbaar agenda-item kreeg geen eigen hulp')
assert(calendar_help.status:find('Tijd: HH:MM', 1, true), 'ontbrekende agendagegevens ontbreken in hulp')

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

-- Succes is geen toestemming om nieuwere edits als gepubliceerd te markeren.
local changed_source = paths.work() .. '/nieuwere-edits.md'
vim.fn.writefile({ 'Oorspronkelijke tekst' }, changed_source)
local changed_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(changed_buf, changed_source)
local changed_name = vim.api.nvim_buf_get_name(changed_buf)
vim.api.nvim_buf_set_lines(changed_buf, 0, -1, false, { 'Oorspronkelijke tekst' })
local tick = vim.api.nvim_buf_get_changedtick(changed_buf)
local newer = { 'c: Nieuwe fotograaf', '', 'Nieuwere tekst', '', '## Kalender', 'Nieuw item' }
vim.api.nvim_buf_set_lines(changed_buf, 0, -1, false, newer)
local archive = test_root .. '/gepubliceerd.md'
vim.fn.writefile({ '# Gepubliceerde versie', '', 'Oorspronkelijke tekst' }, archive)
local safe, _, cleaned, preserved = ai._finalize_published_buffer(
  changed_buf, changed_source, { '**Verstuurd**' }, archive, tick
)
assert(safe and not cleaned and preserved, 'nieuwe edits werden opgeruimd na publicatie')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(changed_buf, 0, -1, false), newer),
  'succesroute wijzigde nieuwere tekst/agenda/foto')
assert(vim.bo[changed_buf].modifiable and not vim.bo[changed_buf].readonly and vim.bo[changed_buf].modified,
  'nieuwere edits zijn niet meer bewerkbaar of staan ten onrechte als opgeslagen')
assert(vim.fn.filereadable(changed_source) == 1, 'nieuwer werkbestand is verwijderd')
assert(vim.api.nvim_buf_get_name(changed_buf) == changed_name, 'werkbuffer is losgekoppeld')
local marker = changed_name .. '.pubble-recovery.json'
assert(vim.json.decode(table.concat(vim.fn.readfile(marker), '\n')).completed,
  'bron kan na heropenen opnieuw worden gepubliceerd')
local help = ai._article_context_help(changed_buf)
assert(help.title == 'Gepubliceerd, nieuwere wijzigingen behouden', 'contexthelp mist het verschil met de gepubliceerde versie')
local recovery = require('publication_recovery')
local dialog = require('user_dialog')
dialog.confirm = function() return 1 end
assert(recovery.review_conflict(changed_buf), 'aw startte opnieuw een publicatie')
local view = vim.api.nvim_get_current_buf()
assert(view ~= changed_buf and vim.bo[view].buftype == 'nofile' and vim.bo[view].readonly
  and not vim.bo[view].modifiable, 'archiefvergelijking is geen aparte alleen-lezen weergave')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(view, 0, -1, false), vim.fn.readfile(archive)),
  'archiefvergelijking mist de gepubliceerde tekst')
assert(recovery.review_conflict(view), 'archiefweergave kan als nieuw artikel worden verstuurd')
vim.b[changed_buf].failed_send_conflict = nil
assert(recovery.review_conflict(changed_buf), 'heropenen omzeilt de duurzame publicatieblokkade')

vim.fn.delete(test_root, "rf")
print("published review buffer: OK")
