-- Dunne NeoVim-client voor de Python-wijkactie bij De Swollenaer.
local M = {}
local commands = require('texttools_commands')
local workflow_log = require('workflow_log')

local function is_swollenaer(resolved)
  for _, code in ipairs(resolved.editions or {}) do
    if code == 'SW' then return true end
  end
  return false
end

function M.needs_choice(resolved)
  return is_swollenaer(resolved)
    and (resolved.swollenaer_wijk_check == true or resolved.swollenaer_wijk_lookup == true)
end

function M.set_control(buf, name)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if vim.trim(line) == '=== ARTIKEL ===' then
      vim.api.nvim_buf_set_lines(buf, index - 1, index - 1, false, { 'wijk: ' .. name })
      return true
    end
    if line:match('^%s*[Ww]ijk%s*:') then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { 'wijk: ' .. name })
      return true
    end
  end
  return false
end

-- callback: 'continue', 'restart', of een Nederlandse foutmelding.
function M.ensure(buf, article_path, resolved, callback)
  if not M.needs_choice(resolved) then callback('continue'); return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local command = { commands.bin('pubble-wijk'), 'analyse', article_path }
  local trace = workflow_log.start(buf, 'Swollenaer · Wijkcontrole', {
    command = vim.fn.fnamemodify(command[1], ':t'),
  })
  local finished = false
  local function complete(outcome, value, detail)
    if finished then return end
    finished = true
    workflow_log.finish(trace, outcome, detail)
    callback(value)
  end
  local function diagnose(detail)
    workflow_log.diagnostic(buf, 'Swollenaer · Wijkcontrole', detail)
  end
  local options = workflow_log.with_environment({ text = true }, trace)
  local started, start_error = pcall(vim.system, command, options, function(process)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        diagnose({ status = 'stale', reason = 'buffer_changed' })
        complete('stale', 'De artikeltekst is tijdens de wijkcontrole gewijzigd. Druk opnieuw <leader>aw.', {
          error = 'ChangedTick',
        })
        return
      end
      local ok, result = pcall(vim.fn.json_decode, process.stdout or '')
      if process.code ~= 0 or not ok or type(result) ~= 'table' then
        diagnose({
          status = 'failed',
          reason = process.code ~= 0 and 'process_failed' or 'invalid_result',
        })
        complete('failed', 'Wijkcontrole mislukt: ' .. vim.trim(process.stderr or 'onbekende fout'), {
          exit_code = process.code,
          error = ok and 'InvalidResult' or 'InvalidJson',
        })
        return
      end
      local diagnostic = vim.tbl_extend('force', result.diagnostics or {}, {
        status = result.status,
        request_mode = result.request_mode or resolved.swollenaer_wijk_check_mode,
      })
      diagnose(diagnostic)
      if result.status == 'chosen' then
        complete('succeeded', 'continue', { status = 'chosen' })
        return
      end

      local function apply(name, manual)
        if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
          diagnose({ status = 'stale', reason = 'buffer_changed_during_choice' })
          complete('stale', 'De artikeltekst is tijdens de wijkkeuze gewijzigd. Druk opnieuw <leader>aw.', {
            error = 'ChangedTick',
          })
          return
        end
        if not M.set_control(buf, name) then
          diagnose({ status = 'failed', reason = 'missing_article_boundary' })
          complete('failed', 'De artikelgrens ontbreekt; wijk kon niet worden vastgelegd.', {
            error = 'MissingArticleBoundary',
          })
          return
        end
        workflow_log.diagnostic(buf, 'Swollenaer · Wijkkeuze', {
          status = manual and 'confirmed' or 'automatic',
          reason = manual and 'editor_choice' or diagnostic.reason,
          request_mode = diagnostic.request_mode,
          chosen = name,
        })
        local street = type(result.streets) == 'table' and #result.streets == 1 and result.streets[1] or nil
        if not manual or not street or not street.house or name == 'Heel Zwolle' then
          complete('succeeded', 'restart', { status = 'recorded' })
          return
        end
        local save_command = {
          commands.bin('pubble-wijk'), 'onthoud',
          '--street', street.name, '--house', street.house, '--choice', name,
        }
        local save_started, save_error = pcall(vim.system, save_command, workflow_log.with_environment({ text = true }, trace), function(saved)
          vim.schedule(function()
            if saved.code ~= 0 then
              vim.notify('Wijk gekozen, maar adres kon niet worden onthouden: ' .. vim.trim(saved.stderr or ''), vim.log.levels.WARN)
              workflow_log.diagnostic(buf, 'Swollenaer · Wijkcache', {
                status = 'failed',
                reason = 'manual_cache_write_failed',
                chosen = name,
              })
            end
            complete('succeeded', 'restart', { status = 'recorded' })
          end)
        end)
        if not save_started then
          vim.notify('Wijk gekozen, maar adrescache kon niet starten: ' .. tostring(save_error), vim.log.levels.WARN)
          workflow_log.diagnostic(buf, 'Swollenaer · Wijkcache', {
            status = 'failed',
            reason = 'manual_cache_process_failed',
            chosen = name,
          })
          complete('succeeded', 'restart', { status = 'recorded' })
        end
      end

      if result.status == 'citywide' then
        apply(result.suggested or 'Heel Zwolle', false)
        return
      end

      if result.status == 'suggested' and type(result.suggested) == 'string' then
        local evidence = type(result.evidence) == 'table' and result.evidence[1] or nil
        if result.request_mode == 'forced' then
          vim.notify('Wijk voorgesteld: ' .. result.suggested .. (evidence and (' — ' .. evidence) or ''), vim.log.levels.INFO)
          apply(result.suggested, false)
          return
        end
      end

      local options = {}
      local seen = {}
      local function add_option(name)
        if type(name) == 'string' and name ~= '' and not seen[name] then
          seen[name] = true
          table.insert(options, name)
        end
      end
      add_option(result.suggested)
      add_option('Heel Zwolle')
      for _, choice in ipairs(result.choices or {}) do
        add_option(choice.name)
      end
      if #options == 0 then
        diagnose({ status = 'failed', reason = 'no_choices' })
        complete('failed', 'Geen Swollenaer-wijken beschikbaar.', { error = 'NoChoices' })
        return
      end
      local prompt = 'Welke wijk hoort bij dit Swollenaer-bericht?'
      if result.status == 'suggested' then
        prompt = 'Wijk gevonden: ' .. result.suggested .. '. Klopt dit voor het webartikel?'
      end
      if type(result.evidence) == 'table' and result.evidence[1] then
        prompt = prompt .. '\nGevonden: ' .. result.evidence[1]
      end
      require('user_dialog').select(options, { prompt = prompt, required = true }, function(choice)
        if not choice then
          complete('cancelled', 'Verzending geannuleerd: wijk nog niet gekozen.')
          return
        end
        apply(choice, true)
      end)
    end)
  end)
  if not started then
    diagnose({ status = 'failed', reason = 'process_start_failed' })
    complete('failed', 'Wijkcontrole kon niet starten: ' .. tostring(start_error), {
      error = 'ProcessStartError',
    })
  end
end

return M
