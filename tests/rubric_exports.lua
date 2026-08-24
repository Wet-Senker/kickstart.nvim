local layout_export = require('layout_export')
local krant = require('krant')

local tmp = vim.fn.tempname()
local inbox = tmp .. '/inbox'
local photo_root = tmp .. '/krant-fotos'
local desktop = tmp .. '/Desktop'
vim.fn.mkdir(inbox, 'p')
vim.fn.mkdir(photo_root, 'p')
vim.fn.mkdir(desktop, 'p')
vim.env.TEXTTOOLS_INBOX_DIR = inbox
krant.config.photo_root = photo_root
krant.config.stock_images = photo_root .. '/stock'
krant.config.desktop = desktop

local function article(title, body)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    '=== ARTIKEL ===',
    '',
    title,
    '',
    body,
  })
  return buf
end

local function choose_first(items, _, callback)
  assert(items[1], 'keuzemenu is leeg')
  callback(items[1])
end

local function clear_inbox()
  vim.fn.delete(inbox, 'rf')
  vim.fn.mkdir(inbox, 'p')
end

-- Raadspraat: foto nu, definitieve tekst pas na <leader>aw.
local raad_dir = photo_root .. '/raadspraat/CDA'
vim.fn.mkdir(raad_dir, 'p')
vim.fn.writefile({ 'foto' }, raad_dir .. '/Ada Raadslid.jpg')
local raad_buf = article('Eigen Raadspraatkop', 'Aangeleverde Raadspraattekst.')
vim.ui.select = choose_first
vim.fn.writefile({ 'oude foto' }, inbox .. '/oud.jpg')
krant.raadspraat_menu()
assert(layout_export.pending(raad_buf) == nil, 'Raadspraat accepteerde een vervuilde Inbox')
clear_inbox()
krant.raadspraat_menu()
local raad_plan = assert(layout_export.pending(raad_buf), 'Raadspraat exportplan ontbreekt')
assert(raad_plan.dir:match('_gemeentenieuws$'), 'Raadspraat gaat niet naar gemeentenieuws')
assert(raad_plan.txt_name == '1.raadspraatFOTO.txt', 'verkeerde Raadspraattekstnaam')
assert(vim.fn.filereadable(raad_plan.dir .. '/' .. raad_plan.img_name) == 1, 'Raadspraatfoto ontbreekt')
assert(vim.fn.filereadable(raad_plan.dir .. '/' .. raad_plan.txt_name) == 0, 'Raadspraattekst is te vroeg geschreven')
vim.api.nvim_buf_set_lines(raad_buf, -1, -1, false, { '', 'Correctie na <leader>kt.' })
local raad_path = assert(layout_export.finalize(raad_buf))
assert(table.concat(vim.fn.readfile(raad_path), '\n'):find('Correctie na <leader>kt%.?'), 'Raadspraatcorrectie ontbreekt')

-- Kamper Kiek: uitsluitend gemeentenieuws, nooit de generieke lezersnieuwsmap.
clear_inbox()
vim.fn.writefile({ 'foto' }, inbox .. '/weekfoto.jpg')
local kiek_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(kiek_buf)
vim.api.nvim_buf_set_lines(kiek_buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'De Kamper kiek op de wîêk: 1). Ik zit “op het pluche”. '
    .. 'De brandweer staat 24/7 voor ons klaar. '
    .. '2). Het Oranjefeest is spetterend en speciaal. '
    .. '3). Jong en oud geniet van het Oogstfeest. '
    .. '4). Een bloemetje voor de Vijverhof en haar 60 bewoners. '
    .. '5). Het Stedelijk Museum is nu al schitterend.',
})
local kiek_template
for _, template in ipairs(krant.templates) do
  if template.name == 'Kiek op de wiek (Sander de Rouwe)' then kiek_template = template end
end
assert(kiek_template and kiek_template.no_export, 'Kiek-template onderdrukt generieke export niet')
krant.kamperkiek_flow(kiek_template)
local kiek_plan = assert(layout_export.pending(kiek_buf), 'Kiek-exportplan ontbreekt')
assert(kiek_plan.dir:match('_gemeentenieuws$'), 'Kamper Kiek gaat niet naar gemeentenieuws')
assert(kiek_plan.txt_name == '2.kamperkiekFOTO.txt', 'verkeerde Kiek-tekstnaam')
assert(vim.fn.filereadable(kiek_plan.dir .. '/' .. kiek_plan.txt_name) == 0, 'Kiektekst is te vroeg geschreven')
assert(vim.fn.glob(desktop .. '/*_lezersnieuws') == '', 'Kamper Kiek maakte toch lezersnieuws aan')
local kiek_text = table.concat(vim.api.nvim_buf_get_lines(kiek_buf, 0, -1, false), '\n')
assert(
  kiek_text:find('newspaper:\n  working_title: "z - 1 Kamper Kiek"', 1, true),
  'Kamper Kiek kreeg niet de vaste z-werktitel'
)
assert(kiek_text:find('prio: 1', 1, true), 'Kamper Kiek verloor de bestaande prioriteitscode')
assert(kiek_text:find('=== ARTIKEL ===', 1, true), 'Kamper Kiek verloor de artikelgrens')
assert(kiek_text:find('De Kamper Kiek op de wîêk', 1, true), 'vaste Kamper-Kiekkop ontbreekt')
assert(
  kiek_text:find('In De Brug kijkt burgemeester Sander de Rouwe wekelijks in fotovorm terug', 1, true),
  'vaste Kamper-Kiekintro ontbreekt'
)
assert(not kiek_text:find('De Kamper kiek op de wîêk:', 1, true), 'aangeleverde rubriekkop bleef dubbel staan')
assert(
  kiek_text:find('1. Ik zit “op het pluche”. De brandweer staat 24/7 voor ons klaar.', 1, true),
  'eerste Kiekonderdeel is inhoudelijk gewijzigd'
)
assert(
  kiek_text:find('\n1. Ik zit “op het pluche”.', 1, true)
    and kiek_text:find('\n2. Het Oranjefeest', 1, true)
    and kiek_text:find('\n3. Jong en oud geniet', 1, true)
    and kiek_text:find('\n4. Een bloemetje voor de Vijverhof', 1, true)
    and kiek_text:find('\n5. Het Stedelijk Museum', 1, true),
  'Kieknummering staat niet op eigen regels:\n' .. kiek_text
)
local nette_kiek = krant._normalize_kamper_kiek({
  'De Kamper Kiek op de wîêk',
  '',
  'In De Brug kijkt burgemeester Sander de Rouwe wekelijks in fotovorm terug op de afgelopen week.',
  '',
  '1. Eerste onderdeel staat al goed.',
  '2. Tweede onderdeel staat ook goed.',
})
assert(
  table.concat(nette_kiek, '\n') == '1. Eerste onderdeel staat al goed.\n2. Tweede onderdeel staat ook goed.',
  'al nette Kamper-Kieknummering werd onnodig veranderd'
)

-- Ondernemen: titel wordt ingevuld en de oorspronkelijke kop wordt niet dubbel.
clear_inbox()
local ondernemen_dir = photo_root .. '/ondernemen_in_kampen'
vim.fn.mkdir(ondernemen_dir, 'p')
vim.fn.writefile({ 'foto' }, ondernemen_dir .. '/Bert Ondernemer.jpg')
vim.fn.writefile({
  'naam: Bert Ondernemer',
  'functie: directeur van Voorbeeld BV',
  'fotograaf: Testfotograaf',
}, ondernemen_dir .. '/personen.md')
local ondernemen_buf = article('Een ondernemende kop', 'De actuele columntekst.')
vim.ui.select = choose_first
krant.ondernemen_menu()
local ondernemen_plan = assert(layout_export.pending(ondernemen_buf), 'Ondernemen-exportplan ontbreekt')
assert(ondernemen_plan.dir:match('_ondernemen_in_kampen$'), 'Ondernemen gaat naar verkeerde map')
assert(vim.fn.filereadable(ondernemen_plan.dir .. '/' .. ondernemen_plan.txt_name) == 0, 'Ondernementekst is te vroeg geschreven')
local ondernemen_text = table.concat(vim.api.nvim_buf_get_lines(ondernemen_buf, 0, -1, false), '\n')
assert(ondernemen_text:find('Column Ondernemen in Kampen: Een ondernemende kop', 1, true), 'Ondernementitel is niet ingevuld')
assert(not ondernemen_text:find('{{titel}}', 1, true), 'Ondernemen liet een titelplaceholder staan')

-- Gewone template: historische {{title}} wordt uit de bestaande kop gevuld.
local generic_buf = article('Titel uit bron', 'Tekst uit bron.')
assert(krant.apply_template_by_name('Column Natuurvereniging', {}, generic_buf))
local generic_plan = assert(layout_export.pending(generic_buf), 'generiek exportplan ontbreekt')
assert(generic_plan.dir:match('_lezersnieuws$'), 'gewone template gaat niet naar lezersnieuws')
local generic_text = table.concat(vim.api.nvim_buf_get_lines(generic_buf, 0, -1, false), '\n')
assert(generic_text:find('Column Natuurvereniging: Titel uit bron', 1, true), '{{title}} is niet automatisch ingevuld')
assert(not generic_text:find('{{title}}', 1, true), 'historische titelplaceholder bleef staan')

vim.fn.delete(tmp, 'rf')
print('rubric exports: OK')
