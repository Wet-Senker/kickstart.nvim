-- Zonder foto meteen vragen, niet pas na alle voorbereiding.
--
-- De keuze werd voorgelegd ná de doublurecontrole, twee AI-calls, de
-- planningsuggesties en het planningsscherm. Dat is allemaal voor niets als het
-- antwoord toch 'concept' of 'annuleren' is, terwijl de fotostatus al bekend is
-- zodra de deterministische resolve klaar is.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local dialog = require 'user_dialog'

-- De vraag noemt allebei de uitwegen en zet Annuleren als standaard.
local asked
local original_confirm = dialog.confirm
dialog.confirm = function(prompt, buttons, default)
  asked = { prompt = prompt, buttons = buttons, default = default }
  return 2
end
local choice = ai._missing_photo_choice()
dialog.confirm = original_confirm

assert(choice == 2, 'de keuze wordt niet doorgegeven')
assert(asked.prompt:find('geen foto', 1, true), 'de reden ontbreekt')
assert(asked.prompt:find('Pubble Inbox', 1, true), 'er staat niet waar de foto hoort')
assert(asked.buttons:find('Ongepubliceerd plaatsen', 1, true), 'de conceptroute ontbreekt')
assert(asked.buttons:find('Annuleren', 1, true), 'annuleren ontbreekt')
assert(asked.default == 2, 'niet Annuleren als standaard; een reflexmatige Enter zou dan publiceren')

-- De bestaande waarborg vlak voor verzending blijft het vangnet.
local allowed, message = ai._active_publication_photo_guard { has_photo = false }
assert(allowed == false, 'de laatste waarborg is verdwenen')
assert(type(message) == 'string' and message:find('geen foto', 1, true),
  'de waarborg meldt niet waarom')

local ok_allowed = ai._active_publication_photo_guard { has_photo = true }
assert(ok_allowed == true, 'een artikel mét foto wordt tegengehouden')

-- De vroege controle staat vóór het zware werk in het verzendpad.
local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')
local source = table.concat(vim.fn.readfile(repo_root .. '/lua/ai_text.lua'), '\n')
local early = source:find('M._missing_photo_choice()', 1, true)
local duplicate_stage = source:find('check_duplicate_stage(buf, codes, "verzenden"', 1, true)
  or source:find('check_duplicate_stage', source:find('resolved_publication = resolved', 1, true) or 1, true)
assert(early, 'de vroege controle ontbreekt in het verzendpad')
assert(not duplicate_stage or early < duplicate_stage,
  'de fotocontrole staat nog achter de doublurecontrole')

print 'missing photo early: OK'
