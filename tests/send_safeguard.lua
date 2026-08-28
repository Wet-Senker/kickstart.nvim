local ai = require 'ai_text'

local imported = [[
Oorspronkelijke kop van artikel

KAMPEN - De gemeente presenteert vandaag een uitgebreid plan voor de binnenstad. Het plan beschrijft nieuwe bomen, bredere stoepen en extra ruimte voor fietsers. Bewoners kunnen de komende weken reageren op de voorstellen.

De uitvoering begint volgens het college volgend voorjaar. Eerst worden kabels en leidingen vervangen. Daarna volgen de bestrating, verlichting en nieuwe groenstroken in verschillende straten.
]]

local metadata_only = [[
e: B
prio: 2

=== ARTIKEL ===

]] .. imported .. [[

---

## Facebook

Een losse Facebooktekst.
]]

assert(
  ai._editorial_body_text(vim.split(metadata_only, '\n', { plain = true })) == vim.trim(imported),
  'controleregels en socialsecties telden ten onrechte als artikelbewerking'
)
assert(not ai._substantially_changed_since_import(imported, metadata_only), 'alleen workflowmetadata gold ten onrechte als substantiële wijziging')

local rewritten = [[
Binnenstad krijgt meer groen en ruimte

KAMPEN - De binnenstad wordt vanaf volgend voorjaar opnieuw ingericht. De gemeente wil bomen planten, stoepen verbreden en fietsers meer ruimte geven. Inwoners kunnen de plannen de komende weken bekijken en erop reageren.

Voordat de straten een nieuwe inrichting krijgen, worden eerst kabels en leidingen vernieuwd. Vervolgens pakt de gemeente de bestrating en verlichting aan en worden in meerdere straten groenstroken aangelegd.
]]
assert(ai._substantially_changed_since_import(imported, rewritten), 'een duidelijke redactionele herschrijving werd niet als substantieel gezien')

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(imported, '\n', { plain = true }))
ai._capture_import_baseline(buf)

local scheduled_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(scheduled_buf, 0, -1, false, vim.split(imported, '\n', { plain = true }))
ai._schedule_article_autodetect(scheduled_buf)
assert(vim.b[scheduled_buf].send_import_body == vim.trim(imported), 'de importplanner legde de oorspronkelijke body niet direct vast')

local unchanged_reason = ai._send_safeguard_reason(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
assert(unchanged_reason and unchanged_reason:find('niet volledig door AI herschreven', 1, true), 'een onbewerkte import gaf geen gerichte waarschuwing')

vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(rewritten, '\n', { plain = true }))
local manual_reason = ai._send_safeguard_reason(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
assert(
  manual_reason and manual_reason:find('geen volledige AI-herschrijving', 1, true),
  'een handmatige substantiële bewerking passeerde zonder AI-waarschuwing'
)

ai._mark_ai_rewrite_completed(buf)
assert(ai._send_safeguard_reason(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false)) == nil, 'AI-rewrite plus substantiële wijziging activeerde de safeguard')

vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(imported, '\n', { plain = true }))
local similar_after_ai = ai._send_safeguard_reason(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
assert(similar_after_ai and similar_after_ai:find('wijkt', 1, true), 'een vrijwel onveranderde AI-uitvoer passeerde zonder waarschuwing')

local confirmations = 0
local original_confirm = ai._send_safeguard_confirm
ai._send_safeguard_confirm = function()
  confirmations = confirmations + 1
  return 1
end
local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

-- De extra waarschuwing is een gewone ja/nee-vraag. Nee is de veilige
-- standaard; de gebruiker hoeft geen afwijkende T/A-menukeuze te onthouden.
local original_vim_confirm = vim.fn.confirm
local prompt_checked = false
vim.fn.confirm = function(message, choices, default)
  assert(message:find("Toch publiceren?", 1, true), "de safeguard stelt geen duidelijke publicatievraag")
  assert(choices == "&Ja\n&Nee", "de safeguard gebruikt niet de verwachte j/n-keuzes")
  assert(default == 2, "Nee is niet de veilige standaardkeuze")
  prompt_checked = true
  return 2
end
assert(original_confirm("Testreden") == 2, "de nee-keuze werd niet teruggegeven")
vim.fn.confirm = original_vim_confirm
assert(prompt_checked, "de j/n-bevestiging is niet aangeroepen")

assert(ai._confirm_send_safeguard(buf, current_lines), 'bevestigde verzending werd geblokkeerd')
assert(ai._confirm_send_safeguard(buf, current_lines), 'onthouden bevestiging werd geblokkeerd')
assert(confirmations == 1, 'dezelfde ongewijzigde body vroeg meermaals om bevestiging')
ai._send_safeguard_confirm = original_confirm

-- Integratie: Annuleren stopt <leader>aw vóór het eerste subprocess en dus
-- vóór iedere mogelijke Pubble-write.
local blocked_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(blocked_buf, 0, -1, false, vim.split(imported, '\n', { plain = true }))
ai._capture_import_baseline(blocked_buf)
local blocked_prompted = false
ai._send_safeguard_confirm = function()
  blocked_prompted = true
  return 2
end
local original_system = vim.system
vim.system = function() error 'verzending startte ondanks geannuleerde safeguard' end
local ok, send_error = pcall(ai.pubble_send, blocked_buf)
vim.system = original_system
ai._send_safeguard_confirm = original_confirm
assert(ok, send_error)
assert(blocked_prompted, '<leader>aw sloeg de safeguard over')

print 'send safeguard: OK'
