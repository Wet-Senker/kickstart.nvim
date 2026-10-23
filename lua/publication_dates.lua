-- Dunne UI-adapter voor de gedeelde, AI-vrije publicatiedatumcontrole.
local M = {}
local notifications = require('texttools_notify')
local commands = require('texttools_commands')
local requests = {}
local workflow = require('workflow_log')
local revisions = require('buffer_revision')
local failure_messages = {
  invalid_documents = 'De artikelteksten zijn ongeldig doorgegeven.',
  invalid_display_dates = 'De publicatiedatums zijn ongeldig doorgegeven.',
  invalid_editions = 'De editie ontbreekt of is ongeldig.',
  date_review_failed = 'De artikel- of datumgegevens konden niet worden gecontroleerd.',
  confirmation_not_allowed = 'Pas eerst de aankondigingszin of de publicatiedatum aan.',
  invalid_response = 'De controle gaf geen geldig antwoord.',
  invalid_approval = 'De controle gaf geen geldige bevestiging terug.',
  process_failed = 'Het controleproces is gestopt.',
  process_timeout = 'Het controleproces reageerde niet binnen 10 seconden.',
  process_start_failed = 'Het controleproces kon niet starten.',
}

function M.review(buf, file, editions, dates, done)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local before = revisions.capture(buf)
  local transition
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
  local function finish(action, failure, result)
    if requests[buf] ~= request then return end
    requests[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].publication_date_review_pending = nil end
    if failure then
      workflow.diagnostic(buf, 'Publicatie · Datumcontrolefout', { reason = failure, status = 'failed' })
    end
    workflow.finish(trace, failure and 'failed' or (action == 'ready' and 'succeeded' or 'cancelled'), {
      reason = failure or action,
      exit_code = result and result.code,
      signal = result and result.signal,
    })
    done(action, transition)
  end
  local function fail(reason, result)
    notifications.notify('Datumcontrole mislukt: ' .. failure_messages[reason]
      .. ' Er is niets verzonden. Bekijk :TexttoolsLog.', vim.log.levels.ERROR, { buf = buf })
    finish('cancel', reason, result)
  end
  local function run(approve)
    -- Leeg betekent direct plaatsen. Lua {} wordt standaard JSON [], terwijl
    -- de gedeelde controle een datummapping {} verwacht. Niet de validatie
    -- versoepelen: alleen de lege clientrepresentatie expliciet maken.
    local date_values = dates
    if dates == nil or (type(dates) == 'table' and next(dates) == nil) then
      date_values = vim.empty_dict()
    end
    local cmd = { commands.bin('python'), '-m', 'texttools.publication_dates_cli',
      '--editions', table.concat(editions, ','), '--display-dates', vim.json.encode(date_values), '--documents' }
    if approve then table.insert(cmd, '--approve') end
    local opts = workflow.with_environment({ text = true, stdin = vim.json.encode(documents), timeout = 10000 }, trace)
    local started = pcall(notifications.system, cmd, opts,
      notifications.schedule_wrap(function(result)
        if not current() then
          if requests[buf] == request then
            notifications.notify('Tekst gewijzigd tijdens datumcontrole; start de verzending opnieuw.', vim.log.levels.WARN)
            finish('cancel')
          end
          return
        end
        local ok, review = pcall(vim.json.decode, result.stdout or '')
        if result.code ~= 0 or not ok or type(review) ~= 'table' or review.version ~= 1
            or type(review.ready) ~= 'boolean' or review.error_code ~= nil then
          local reason = result.code == 124 and 'process_timeout'
            or (result.code ~= 0 and 'process_failed' or 'invalid_response')
          if ok and type(review) == 'table' and review.version == 1
              and type(review.error_code) == 'string' and failure_messages[review.error_code] then
            reason = review.error_code
          end
          fail(reason, result)
          return
        end
        if approve then
          if not review.ready or type(review.markdown) ~= 'string' or type(review.editor_markdown) ~= 'string' then
            fail('invalid_approval', result); return
          end
          -- De Python-actie voegt alleen de bron-/datumgebonden goedkeuring toe.
          vim.fn.writefile(vim.split(review.markdown, '\n', { plain = true }), file)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(review.editor_markdown, '\n', { plain = true }))
          transition = { before = before, after = revisions.capture(buf) }
          notifications.workflow('Tekst- en datumcontrole afgerond: je bevestiging is opgeslagen.', vim.log.levels.INFO,
            { buf = buf, kind = 'success' })
          finish('ready')
        elseif review.ready then
          local message = review.approved == true and 'Tekst- en datumcontrole afgerond: de eerdere bevestiging is nog geldig.'
            or (type(review.issues) == 'table' and #review.issues == 0
              and 'Tekst- en datumcontrole afgerond: geen aandachtspunten gevonden.' or 'Tekst- en datumcontrole afgerond.')
          notifications.workflow(message, vim.log.levels.INFO, { buf = buf, kind = 'success' })
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
          require('user_dialog').select(items, {
            prompt = table.concat(prompt, '\n'), native = true, source_buf = buf,
          }, function(choice)
            if not current() then finish('cancel'); return end
            if choice == items[1] and review.can_confirm then run(true)
            elseif choice == 'Publicatiedatum aanpassen' then finish('dates')
            elseif choice == 'Tekst zelf aanpassen' then finish('edit')
            else finish('cancel') end
          end)
        end
      end))
    if not started then
      fail('process_start_failed')
    end
  end
  run(false)
end

return M
