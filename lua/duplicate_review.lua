-- Transport for the shared Python review action. No fingerprint/state rules here.
local M = {}
local notifications = require 'texttools_notify'
local commands = require 'texttools_commands'

function M.apply(buf, report, selections, done, reviewed_markdown, allow_source_changes, attempt)
  if not vim.api.nvim_buf_is_valid(buf) then done(false); return end
  local revision = require('buffer_revision').capture(buf)
  local markdown = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  local function handle(process)
    notifications.schedule(function()
      local ok, data = pcall(vim.json.decode, process.stdout or '')
      if process.code ~= 0 or not ok or type(data) ~= 'table' or data.version ~= 1
          or type(data.markdown) ~= 'string' then
        notifications.notify('Doublurekeuzes niet opgeslagen: ' .. vim.trim(process.stderr or ''),
          vim.log.levels.ERROR, { buf = buf })
        done(false); return
      end
      if not vim.api.nvim_buf_is_valid(buf) or not require('buffer_revision').matches(buf, revision) then
        if allow_source_changes and vim.api.nvim_buf_is_valid(buf) and (attempt or 0) < 2 then
          -- Only the decision state is owned by this action. Re-run the small
          -- local merge on the latest text, never write back the old snapshot.
          M.apply(buf, report, selections, done, reviewed_markdown, true, (attempt or 0) + 1)
          return
        end
        notifications.notify('Artikel gewijzigd; doublurekeuzes niet toegepast. Beoordeel opnieuw.', vim.log.levels.WARN, { buf = buf })
        done(false); return
      end
      require('article_notices').replace_content(buf, vim.split(data.markdown, '\n', { plain = true }))
      local summaries = data.summaries or {}
      local summary = #summaries > 0 and table.concat(summaries, '; ')
        or 'Geen onderdelen overgeslagen wegens bevestigde doublures.'
      notifications.workflow(summary .. ' Verder bewerken kan; <leader>aw start bewust de verzending.',
        vim.log.levels.INFO, { buf = buf, action = 'Doublurekeuzes', notice_key = 'duplicate-selection', resolved = true })
      done(true)
    end)
  end
  local started, err = pcall(notifications.system, { commands.bin('python'), '-m', 'texttools.duplicate_selection' }, {
    text = true, stdin = vim.json.encode { markdown = markdown, report = report,
      reviewed_markdown = reviewed_markdown,
      allow_source_changes = allow_source_changes == true,
      selections = next(selections) and selections or vim.empty_dict() },
    texttools_activity = { action = 'Doublurekeuzes bewaren' },
  }, handle)
  if not started then handle { code = 1, stderr = tostring(err) } end
end

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
