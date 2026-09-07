local ai = require('ai_text')
local krant = require('krant')
local rules = vim.json.decode(table.concat(vim.fn.readfile(require('texttools_commands').path('src', 'texttools', 'column_recognition.json')), '\n'))
local covered = {}
for _, rule in ipairs(rules) do covered[rule.template_name] = true end
for _, template in ipairs(krant.templates) do
  assert(covered[template.name], 'template ontbreekt in herkenningscatalogus: ' .. template.name)
end
local tmp = vim.fn.tempname()
local inbox = tmp .. '/inbox'
vim.fn.mkdir(inbox, 'p')
vim.env.TEXTTOOLS_INBOX_DIR = inbox
krant.config.desktop = tmp .. '/Desktop'
krant.config.photo_root = tmp .. '/photos'
krant.config.stock_images = tmp .. '/stock'
vim.fn.mkdir(krant.config.stock_images, 'p')
vim.fn.mkdir(krant.config.photo_root .. '/raadspraat/CDA', 'p')
vim.fn.mkdir(krant.config.photo_root .. '/ondernemen_in_kampen', 'p')
vim.fn.writefile({ 'raadsfoto' }, krant.config.photo_root .. '/raadspraat/CDA/Ada Raadslid.jpg')
vim.fn.writefile({ 'ondernemersfoto' }, krant.config.photo_root .. '/ondernemen_in_kampen/Bert Ondernemer.jpg')
vim.fn.writefile({ 'stock' }, krant.config.stock_images .. '/hondenhoek.jpg')
ai._duplicate_stage_runner = function(_, done) done(true, { performed = false, candidates = {} }) end
ai._rubric_confirm = function(d)
  assert(not d.candidate.explicit or d.candidate.id == 'natuurvereniging' or d.candidate.id == '112', 'expliciete rubriek onnodig bevestigd')
  return d.candidate
end
krant._choose_detected_person = function(items) return items[1] end
vim.ui.select = function() error('importflow mag geen fzf-menu openen') end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function run(label, id, author)
  for _, path in ipairs(vim.fn.glob(inbox .. '/*', false, true)) do vim.fn.delete(path) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', label, '', 'Een actuele titel', '',
    'De volledige columntekst blijft intact.', '', author or '',
  })
  ai._article_autodetect(buf)
  assert(vim.wait(5000, function() return vim.b[buf].recognized_rubric == id end, 10), label .. ' niet toegepast')
  assert(text(buf):find('De volledige columntekst blijft intact.', 1, true))
  return buf
end
local council = run('Raadspraat', 'raadspraat')
assert(text(council):find('Raadspraat CDA:', 1, true))
assert(vim.fn.filereadable(inbox .. '/Ada Raadslid.jpg') == 1)
local business = run('Ondernemen in Kampen', 'ondernemen')
assert(text(business):find('Column Ondernemen in Kampen: Een actuele titel', 1, true))
assert(vim.fn.filereadable(inbox .. '/Bert Ondernemer.jpg') == 1)
local nature = run('Natuurvereniging IJsseldelta', 'natuurvereniging')
assert(text(nature):find('Column Natuurvereniging: Een actuele titel', 1, true))
local emergency = run('112 nieuws', '112')
assert(text(emergency):find('112: Een actuele titel', 1, true), '112-label werd ten onrechte artikelkop')
local birds = run('Vogelgroep Kampen', 'vogelgroep')
assert(text(birds):find('Column Vogelgroep Kampen: Een actuele titel', 1, true))
run('Hondenhoek', 'hondenhoek')

-- Een persoonsnaam uit de fotomap werkt ook zonder rubrieklabel, na bevestiging.
local personal = run('Een actuele titel', 'ondernemen', 'Bert Ondernemer')
assert(text(personal):find('Bert Ondernemer', 1, true))

-- Een andere actieve buffer mag niet het doel worden van een latere persoonskeuze.
for _, path in ipairs(vim.fn.glob(inbox .. '/*', false, true)) do vim.fn.delete(path) end
local target = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(target, 0, -1, false, { '=== ARTIKEL ===', '', 'Titel', '', 'Eigen body.' })
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other)
local before = text(target)
krant._choose_detected_person = function(items)
  vim.api.nvim_buf_set_lines(target, -1, -1, false, { 'Nieuwere bewerking.' })
  return items[1]
end
assert(not krant.apply_detected_rubric('ondernemen', target, {}))
assert(text(target) == before .. '\nNieuwere bewerking.', 'persoonskeuze overschreef een nieuwere bewerking')
assert(text(other) == '', 'persoonskeuze wijzigde andere buffer')
vim.fn.delete(tmp, 'rf')
print('rubric labels: OK')
