-- Optional integration against the locally installed plugin; unit coverage in
-- task_completion.lua remains available on minimal/offline CI installations.
local plugin = vim.fn.glob(vim.fn.stdpath('data') .. '/site/pack/*/opt/fidget.nvim', false, true)[1]
if not plugin then print('task completion Fidget: SKIP (plugin niet geïnstalleerd)'); return end
vim.opt.runtimepath:append(plugin)
local display = require 'task_display'
require('fidget').setup {
  progress = { display = { overrides = {
    texttools_tasks = { ttl = display.done_ttl, skip_history = true, render_limit = 5, icon = display.icon, name = display.group_name },
  } } },
}
local notification = require 'fidget.notification'
local model = notification.model
local captured, update = nil, model.update
model.update = function(now, configs, state, ...)
  captured = state
  return update(now, configs, state, ...)
end
local function items(group)
  for _, entry in ipairs(captured and captured.groups or {}) do
    if entry.key == (group or 'texttools_tasks') then return entry.items end
  end
  return {}
end
local function wait(test) assert(vim.wait(1000, test, 5), 'Fidget-update bleef hangen') end
display.show { { key = 'a', text = 'Controleren' } }
wait(function() return #items() == 1 end)
assert(items()[1].expires_at == math.huge, 'lopende taak kreeg een vervaltijd')
display.complete('a', 'applied')
display.show {}
wait(function() return items()[1] and items()[1].data == true end)
local done = items()[1]
assert(done.message == '' and done.annote == '✓ Controleren')
assert(display.icon(0, items()) == '', 'onbevestigde voltooiing kreeg een groepsvinkje')
local rendered = require('fidget.notification.view').render_item(done, { annote_separator = ' ' }, 1)
assert(rendered and #rendered > 0, 'lege berichttekst verstopte de resultaatregel')
assert(math.abs(done.expires_at - done.last_updated - 8) < 0.01, 'native Fidget-leestijd is niet acht seconden')
local expiry = done.expires_at
display.show {}
assert(done.expires_at == expiry, 'leestijd werd tijdens verversen herstart')
display.show { { key = 'a', text = 'Controleren' } }
wait(function() return #items() == 2 end)
model.tick(expiry - 0.01, captured)
assert(#items() == 2, 'vinkje verdween vóór acht seconden')
model.tick(expiry + 0.01, captured)
assert(#items() == 1 and not items()[1].data, 'vervallen vinkje raakte een nieuwe run')
notification.notify('Andere melding', nil, { group = 'other', ttl = math.huge })
wait(function() return #items('other') == 1 end)
-- Native finish/notify is scheduled. Hiding must clear those late messages too.
display.show {}
display.hide()
vim.wait(30, function() return false end)
assert(#items() == 0, 'late native finish heropende de taakgroep vóór een keuze')
assert(#items('other') == 1, 'verbergen wiste meldingen van andere plugins')
display.show { { key = 'failed', text = 'Herschrijven' } }
wait(function() return #items() == 1 end)
display.complete('failed', 'failed')
wait(function() return items()[1] and items()[1].data == true end)
assert(items()[1].annote == '✗ Herschrijven mislukt' and display.icon(0, items()) == '',
  'mislukte taak kreeg het standaard Fidget-succesvinkje')
-- Keuzevensters mogen bestaande voltooiingen alleen verbergen, niet wissen.
local before_hide = items()[1]
local original_expiry = before_hide.expires_at
display.suspend({})
assert(items()[1] == before_hide, 'een keuzevenster wiste de nog leesbare laatste melding')
local function rendered_group()
  for _, entry in ipairs(captured.groups) do
    if entry.key == 'texttools_tasks' then
      return require('fidget.notification.view').render(0, { entry })
    end
  end
  return {}
end
assert(#rendered_group() == 0, 'tijdelijk verborgen groep staat voor het keuzevenster')
display.show({})
assert(#rendered_group() > 0 and items()[1].expires_at == original_expiry,
  'terugkeer herstelde de laatste melding niet of verlengde haar leestijd')
display.suspend { { key = 'late', text = 'Kalender', action = 'Kalender' } }
wait(function() return #items() == 2 end)
display.complete('late', 'applied')
wait(function() return items()[1].data and items()[2].data end)
assert(#rendered_group() == 0, 'late finish verscheen voor een keuzevenster')
display.show({})
local rendered = rendered_group()
assert(#rendered > 0 and #items() == 2, 'laatste taak afgerond tijdens keuze ging verloren')
-- Technische exits zonder geïnterpreteerde uitkomst worden ook native niet
-- omgezet in een generieke klaar-/Completed-regel of een vals succesvinkje.
notification.clear('texttools_tasks')
display.show { { key = 'unknown', text = 'Technisch proces' } }
wait(function() return #items() == 1 end)
display.show {}
wait(function() return #items() == 0 end)
vim.wait(30, function() return false end)
assert(#items() == 0, 'late native finish herintroduceerde een technische klaar-melding')
-- Alle actieve regels krijgen dezelfde animatie, ook onbekende actienamen,
-- gebundeld werk, andere artikelen en een wachtfase. Resultaattekens blijven.
display.show {
  { key = 'uniform-1', text = 'Herschrijven', action = 'Herschrijven' },
  { key = 'uniform-2', text = 'Doublurecontrole (2)', action = 'Doublurecontrole', count = 2 },
  { key = 'uniform-3', text = 'Kalender', action = 'Kalender', prefix = 'Ander.md · ',
    active_text = 'Ander.md · Wachten op beoordeling…' },
}
wait(function() return #items() == 3 end)
local view = require 'fidget.notification.view'
local function draw(now)
  for _, entry in ipairs(captured.groups) do
    if entry.key == 'texttools_tasks' then return view.render(now, { entry }) end
  end
end
local before, expiry = {}, {}
draw(10)
local prefix = items()[1].texttools_spinner_prefix
assert(prefix and prefix ~= '', 'eerste taak mist de animatie')
for _, item in ipairs(items()) do
  assert(item.texttools_spinner_prefix == prefix and item.annote:sub(1, #prefix) == prefix,
    'niet elke actieve taak heeft hetzelfde bolletje')
  before[item.key], expiry[item.key] = item.annote, item.expires_at
end
draw(10.5)
for _, item in ipairs(items()) do
  assert(item.annote ~= before[item.key] and item.expires_at == expiry[item.key],
    'animatie beweegt niet of verandert de vervaltijd')
  assert(not item.annote:find(prefix, #item.texttools_spinner_prefix + 1, true),
    'renderen stapelt bolletjes op')
end
display.complete('uniform-1', 'applied')
wait(function()
  for _, item in ipairs(items()) do if item.annote == '✓ Artikel herschreven' then return true end end
end)
draw(11)
for _, item in ipairs(items()) do
  if item.data then
    assert(item.annote == '✓ Artikel herschreven' and not item.texttools_spinner_prefix,
      'succes heeft nog een bolletje of verloor zijn vinkje')
  else assert(item.texttools_spinner_prefix, 'overige lopende taken verloren hun bolletje') end
end
display.show {}
notification.clear('texttools_tasks')
-- Dezelfde grens via de werkelijke activity-refresh, ook als de laatste taak
-- tijdens een zwevend keuzevenster eindigt. Geen verdwenen of opnieuw getimede regel.
local activity = require 'article_activity'
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local source = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(source, 0, -1, false, { '=== ARTIKEL ===', '', 'Testartikel.' })
activity.start(source, 'last', 'AI · Tekstcheck')
local function last_item()
  for _, item in ipairs(items()) do
    if item.annote:find('Tekst controleren…', 1, true) or item.annote == '✓ Tekst gecontroleerd' then return item end
  end
end
wait(function() return last_item() and not last_item().data end)
local float_buf = vim.api.nvim_create_buf(false, true)
vim.b[float_buf].user_dialog_source = source
local float_win = vim.api.nvim_open_win(float_buf, true, { relative = 'editor', width = 30, height = 3, row = 1, col = 1 })
wait(function() return #rendered_group() == 0 end)
activity.result(source, 'last', 'applied')
activity.finish(source, 'last')
wait(function() return last_item() and last_item().data end)
local last_done = last_item()
local final_expiry = last_done.expires_at
assert(math.abs(last_done.expires_at - last_done.last_updated - 8) < 0.01)
vim.api.nvim_win_close(float_win, true)
wait(function() return #rendered_group() > 0 end)
assert(last_item() == last_done and last_done.expires_at == final_expiry,
  'de laatste zichtbare voltooiing werd gewist of opnieuw aangemaakt')
notification.clear('other')
model.update = update
print('task completion Fidget: OK')
