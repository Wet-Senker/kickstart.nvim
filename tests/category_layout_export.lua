local krant = require('krant')
local layout = require('layout_export')
local tmp = vim.fn.tempname()
krant.config.desktop = tmp .. '/Desktop'
krant.config.brug = tmp .. '/Documents/1.Brugmedia/Brug'
local week = os.date('%V', tonumber(os.date('%u')) == 1 and os.time() or os.time() + 7 * 86400)
local directory = krant.config.brug .. '/' .. week .. '_ondernemen_in_kampen'
vim.fn.mkdir(directory, 'p')
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B', 'r: nem', '', '=== ARTIKEL ===', '', 'Nieuwe winkel', '', 'De artikeltekst.',
})
local path = tmp .. '/artikel.md'
vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), path)
local raw = vim.fn.system({ require('texttools_commands').bin('pubble-send'), path,
  '--resolve-editions', '--require-article-boundary' })
assert(vim.v.shell_error == 0, raw)
local resolved = vim.json.decode(raw)
assert(resolved.layout_export.section == 'ondernemen_in_kampen', 'rubriek leverde geen exportopdracht')
local ok, err = krant.ensure_category_export(buf, resolved.layout_export)
assert(ok, err)
local plan = assert(layout.pending(buf))
assert(plan.dir == directory, 'bedrijfscategorie gebruikte niet dezelfde Brug-weekmap')
assert(vim.fn.filereadable(directory .. '/' .. plan.txt_name) == 0, 'artikeltekst is voor publicatie geschreven')
assert(krant.ensure_category_export(buf, resolved.layout_export))
assert(vim.deep_equal(plan, layout.pending(buf)), 'herhalen wijzigde het exportplan')
local exported = assert(layout.finalize(buf))
assert(exported == directory .. '/' .. plan.txt_name, 'definitieve tekst belandde in een andere map')
assert(table.concat(vim.fn.readfile(exported), '\n'):find('De artikeltekst.', 1, true), 'tekst ontbreekt')
assert(not table.concat(vim.fn.readfile(exported), '\n'):find('r: nem', 1, true), 'controleregel lekte in export')
print('category layout export: OK')
