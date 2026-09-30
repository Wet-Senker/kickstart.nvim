-- Bij een benodigde kranttijdsversie moet de gebruiker "Alleen website (geen
-- krant)" kunnen kiezen. We stubben user_dialog.confirm en controleren dat die
-- optie in de keuze zit en dat de gekozen index terugkomt.
package.loaded['user_dialog'] = nil
local captured
package.loaded['user_dialog'] = {
  confirm = function(message, options, default)
    captured = { message = message, options = options, default = default }
    return 2  -- "Alleen website (geen krant)"
  end,
  select = function() end,
}

local ai = require('ai_text')

assert(type(ai._newspaper_time_version_choice) == 'function',
  'de kranttijd-keuze ontbreekt')
local choice = ai._newspaper_time_version_choice()

assert(choice == 2, 'de gekozen optie kwam niet terug')
assert(captured.options:find('Alleen website', 1, true),
  'de web-only-optie ontbreekt in de keuze')
assert(captured.options:find('Kranttijdsversie', 1, true),
  'de kranttijdsversie-optie ontbreekt')
assert(captured.message:find('andere tijdsversie', 1, true),
  'de uitleg noemt de kranttijdsversie niet')

print('web only choice: OK')
