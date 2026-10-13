-- Dunne UI-adapter voor de gedeelde, AI-vrije publicatiedatumcontrole.
local M = {}
local commands = require('texttools_commands')
local requests = {}
local workflow = require('workflow_log')

function M.review(buf, file, editions, dates, done)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local request = {}
  requests[buf] = request
  vim.b[buf].publication_date_review_pending = true
  local trace = workflow.start(buf, 'Publicatie · Tekst/datum controleren', { command = 'publication_dates' })
  local documents = {
    publication = table.concat(vim.fn.readfile(file), '\n'),
    editor = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'),
  }
  local function current()
    return vim.api.nvim_buf_is_valid(buf) and requests[buf] == request
      and vim.api.nvim_buf_get_changedtick(buf) == tick
  end
  local function finish(action)
    if requests[buf] ~= request then return end
    requests[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].publication_date_review_pending = nil end
    workflow.finish(trace, action == 'ready' and 'succeeded' or 'cancelled', { reason = action })
    done(action)
  end
  local function run(approve)
    local cmd = { commands.bin('python'), '-m', 'texttools.publication_dates_cli',
      '--editions', table.concat(editions, ','), '--display-dates', vim.json.encode(dates), '--documents' }
    if approve then table.insert(cmd, '--approve') end
    local opts = workflow.with_environment({ text = true, stdin = vim.json.encode(documents), timeout = 10000 }, trace)
    local started = pcall(vim.system, cmd, opts,
      vim.schedule_wrap(function(result)
        if not current() then
          if requests[buf] == request then
            vim.notify('Tekst gewijzigd tijdens datumcontrole; start de verzending opnieuw.', vim.log.levels.WARN)
            finish('cancel')
          end
          return
        end
        local ok, review = pcall(vim.json.decode, result.stdout or '')
        if result.code ~= 0 or not ok or type(review) ~= 'table' or review.version ~= 1 then
          vim.notify('Datumcontrole mislukt; er is niets verzonden.', vim.log.levels.ERROR)
          finish('cancel')
          return
        end
        if approve then
          if not review.ready or type(review.markdown) ~= 'string' or type(review.editor_markdown) ~= 'string' then
            finish('cancel'); return
          end
          -- De Python-actie voegt alleen de bron-/datumgebonden goedkeuring toe.
          vim.fn.writefile(vim.split(review.markdown, '\n', { plain = true }), file)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(review.editor_markdown, '\n', { plain = true }))
          finish('ready')
        elseif review.ready then
          finish('ready')
        else
          local prompt = { 'Tekst en publicatiedatum controleren:' }
          local groups, seen = {}, {}
          for _, issue in ipairs(review.issues or {}) do
            local key = tostring(issue.message) .. '\n' .. tostring(issue.excerpt or '')
            local group = seen[key]
            if not group then
              group = { editions = {}, issue = issue }
              seen[key] = group
              groups[#groups + 1] = group
            end
            group.editions[#group.editions + 1] = tostring(issue.edition)
          end
          for _, group in ipairs(groups) do
            prompt[#prompt + 1] = '[' .. table.concat(group.editions, ', ') .. '] ' .. tostring(group.issue.message)
            if group.issue.excerpt then prompt[#prompt + 1] = '“' .. group.issue.excerpt .. '”' end
          end
          local items = { 'Publicatiedatum aanpassen', 'Tekst zelf aanpassen', 'Annuleren' }
          if review.can_confirm then table.insert(items, 1, 'Gecontroleerd: tekst klopt op de gekozen webdatum') end
          require('user_dialog').select(items, { prompt = table.concat(prompt, '\n'), native = true }, function(choice)
            if not current() then finish('cancel'); return end
            if choice == items[1] and review.can_confirm then run(true)
            elseif choice == 'Publicatiedatum aanpassen' then finish('dates')
            elseif choice == 'Tekst zelf aanpassen' then finish('edit')
            else finish('cancel') end
          end)
        end
      end))
    if not started then
      vim.notify('Datumcontrole kon niet starten; er is niets verzonden.', vim.log.levels.ERROR)
      finish('cancel')
    end
  end
  run(false)
end

return M
