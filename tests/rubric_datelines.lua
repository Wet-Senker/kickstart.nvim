local krant = require('krant')
local tmp = vim.fn.tempname()
local inbox = tmp .. '/inbox'
vim.env.TEXTTOOLS_INBOX_DIR = inbox
krant.config.desktop = tmp .. '/Desktop'
krant.config.stock_images = tmp .. '/stock'
krant.config.photo_root = tmp .. '/photos'
vim.fn.mkdir(inbox, 'p')
vim.fn.mkdir(krant.config.stock_images, 'p')
vim.fn.mkdir(krant.config.photo_root .. '/raadspraat/CDA', 'p')
vim.fn.mkdir(krant.config.photo_root .. '/ondernemen_in_kampen', 'p')
for _, name in ipairs({ 'hondenhoek.jpg', 'open-hof.jpg', 'nog-even-dit.jpg', 'humor.jpg' }) do
  vim.fn.writefile({ 'stock' }, krant.config.stock_images .. '/' .. name)
end
vim.fn.writefile({ 'foto' }, krant.config.photo_root .. '/raadspraat/CDA/Ada.jpg')
vim.fn.writefile({ 'foto' }, krant.config.photo_root .. '/ondernemen_in_kampen/Bert.jpg')
vim.notify = function() end
vim.ui.select = function(items, _, done) done(items[1]) end
krant._choose_detected_person = function(items) return items[1] end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, tmp .. '/article-' .. buf .. '.md')
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', 'Eigen kop', '',
    '**KAMPEN - Mijn volledige rubriektekst.**', '', '---', '',
    '## Facebook', '', 'KAMPEN - Deze socialtekst blijft.', '',
    '## Niet voor publicatie', '> KAMPEN - Privétekst.',
  })
  return buf
end
local function clean(buf)
  assert(vim.wait(5000, function() return not vim.b[buf]._rubric_dateline_pending end, 10), 'datelinecontrole blijft hangen')
  local result = text(buf)
  assert(result:find('**Mijn volledige rubriektekst.**', 1, true), 'rubriekdateline bleef staan')
  assert(result:find('KAMPEN - Deze socialtekst blijft.', 1, true), 'socialsectie gewijzigd')
  assert(result:find('> KAMPEN - Privétekst.', 1, true), 'privésectie gewijzigd')
  assert(result:find('e: B', 1, true), 'editie verdwenen')
end
local function clear_inbox()
  for _, path in ipairs(vim.fn.glob(inbox .. '/*', false, true)) do vim.fn.delete(path) end
end

-- All ordinary templates, including explicit buffer 0, use the shared action.
for _, template in ipairs(krant.templates) do
  if template.name ~= '112 nieuws' then
    local buf = source()
    assert(krant.apply_template_by_name(template.name, {}, 0))
    clean(buf)
  end
end
local emergency = source()
assert(krant.apply_template_by_name('112 nieuws', { prefix = '112 KAMPEN:' }, emergency))
assert(vim.wait(5000, function() return not vim.b[emergency]._rubric_dateline_pending end, 10))
assert(text(emergency):find('**KAMPEN - Mijn volledige rubriektekst.**', 1, true), '112 verloor dateline')

for _, route in ipairs({ 'raadspraat', 'ondernemen', 'hondenhoek' }) do
  clear_inbox()
  local buf = source()
  local finished = false
  local ok, reason = krant.apply_detected_rubric(route, buf, {}, function(success)
    assert(success)
    assert(not text(buf):find('**KAMPEN - Mijn volledige rubriektekst.**', 1, true), 'vervolg begon vóór opschoning')
    finished = true
  end)
  assert(ok and reason == 'pending', 'import wacht niet op datelinecontrole')
  clean(buf)
  assert(finished, 'vervolgcallback ontbreekt')
end
-- Stock menu paths Open Hof and Nog Even Dit are separate from generic apply.
for _, name in ipairs({ 'Open Hof', 'Nog Even Dit' }) do
  clear_inbox()
  local buf = source()
  vim.ui.select = function(items, _, done)
    for _, item in ipairs(items) do if item.name == name then done(item); return end end
    error('stockmenu ontbreekt: ' .. name)
  end
  krant.menu()
  clean(buf)
end
clear_inbox()
vim.fn.writefile({ 'foto' }, inbox .. '/kiek.jpg')
local kiek = source()
local hook_called = false
krant.on_kamper_kiek_applied = function(buf)
  assert(not text(buf):find('**KAMPEN - Mijn volledige rubriektekst.**', 1, true), 'socialtekst haalde datelinecontrole in')
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '> Direct socialresultaat.' })
  hook_called = true
end
for _, template in ipairs(krant.templates) do
  if template.id == 'kamper_kiek' then assert(krant.kamperkiek_flow(template, kiek)) end
end
clean(kiek)
assert(hook_called, 'socialvervolg ontbreekt')
krant.on_kamper_kiek_applied = nil

-- Export-preparation failure must not become successful import recognition.
clear_inbox()
local layout = require('layout_export')
local original_prepare = layout.prepare
layout.prepare = function() return nil, 'Bewuste exportfout' end
local failed = source()
local failed_done
krant.apply_detected_rubric('ondernemen', failed, {}, function(success) failed_done = success end)
clean(failed)
assert(failed_done == false, 'exportfout is als geslaagd gemeld')
layout.prepare = original_prepare

-- A late result cannot overwrite manual edits or another buffer.
local requests, warnings = {}, {}
vim.system = function(command, options, done)
  assert(command[2] == '--rubric-template', 'onverwacht proces')
  requests[#requests + 1] = { options = options, done = done }
  return {}
end
vim.notify = function(message) warnings[#warnings + 1] = message end
local edited = source()
krant._mark_template_applied(edited, 'Raadspraat')
local ai = require('ai_text')
local count_before = #requests
ai.pubble_send(edited)
assert(#requests == count_before, 'verzending begon vóór datelinecontrole')
assert(warnings[#warnings]:find('Rubriektemplate wordt nog gecontroleerd', 1, true))
vim.api.nvim_buf_set_lines(edited, -1, -1, false, { 'Mijn nieuwere bewerking.' })
local newer = text(edited)
local other = source()
local other_before = text(other)
requests[1].done({ code = 0, stdout = vim.json.encode({ version = 1, removed_count = 1,
  markdown = requests[1].options.stdin:gsub('KAMPEN %- Mijn', 'Mijn') }) })
assert(vim.wait(1000, function() return not vim.b[edited]._rubric_dateline_pending end, 5))
assert(text(edited) == newer and text(other) == other_before, 'late callback overschreef buffer')
assert(warnings[#warnings]:find('Artikel gewijzigd', 1, true))

-- Superseded and failed requests settle without losing text.
krant._mark_template_applied(other, 'Raadspraat')
krant._mark_template_applied(other, 'Hondenhoek')
requests[2].done({ code = 0, stdout = vim.json.encode({ version = 1, removed_count = 1, markdown = 'Verouderd' }) })
requests[3].done({ code = 1, stderr = 'fout' })
assert(vim.wait(1000, function() return not vim.b[other]._rubric_dateline_pending end, 5))
assert(text(other) == other_before and not vim.b[other]._rubric_dateline_pending)
assert(warnings[#warnings]:find('mislukt', 1, true))
vim.fn.delete(tmp, 'rf')
print('rubric datelines: OK')
