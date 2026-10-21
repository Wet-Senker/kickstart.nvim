-- Transport for the shared Python review action. No fingerprint/state rules here.
local M = {}
local notifications = require 'texttools_notify'
local commands = require 'texttools_commands'

function M.mark_agenda(key, done)
  if type(key) ~= 'string' or key == '' then
    notifications.notify('Python-kern mist paarsleutels. Werk Texttools bij en controleer opnieuw.', vim.log.levels.ERROR)
    done(false)
    return
  end
  local function handle(process)
    notifications.schedule(function()
      local ok, response = pcall(vim.json.decode, process.stdout or '')
      if process.code ~= 0 or not ok or type(response) ~= 'table'
          or response.schema_version ~= 1 or response.marked_count ~= 1 then
        notifications.notify('Beoordeling niet opgeslagen. Probeer m opnieuw. '
          .. vim.trim(process.stderr or ''), vim.log.levels.ERROR)
        done(false)
        return
      end
      done(true)
    end)
  end
  local started, err = pcall(notifications.system, { commands.bin('python'), '-m', 'texttools.agenda_cli', '--json', 'doublure-geen' }, {
    text = true, stdin = vim.json.encode { review_keys = { key } },
    texttools_activity = { action = 'Agenda · Geen doublure opslaan' },
  }, handle)
  if not started then handle { code = 1, stderr = tostring(err) } end
end

return M
