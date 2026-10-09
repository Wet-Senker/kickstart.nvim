-- Dunne NeoVim-client voor de Python-wijkactie bij De Swollenaer.
local M = {}
local commands = require('texttools_commands')

local function is_swollenaer(resolved)
  for _, code in ipairs(resolved.editions or {}) do
    if code == 'SW' then return true end
  end
  return false
end

function M.needs_choice(resolved)
  return is_swollenaer(resolved) and resolved.swollenaer_wijk_lookup == true
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
  vim.system(command, { text = true }, function(process)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        callback('De artikeltekst is tijdens de wijkcontrole gewijzigd. Druk opnieuw <leader>aw.')
        return
      end
      local ok, result = pcall(vim.fn.json_decode, process.stdout or '')
      if process.code ~= 0 or not ok or type(result) ~= 'table' then
        callback('Wijkcontrole mislukt: ' .. vim.trim(process.stderr or 'onbekende fout'))
        return
      end
      if result.status == 'chosen' then callback('continue'); return end

      local function apply(name, manual)
        if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_buf_get_changedtick(buf) ~= tick then
          callback('De artikeltekst is tijdens de wijkkeuze gewijzigd. Druk opnieuw <leader>aw.')
          return
        end
        if not M.set_control(buf, name) then
          callback('De artikelgrens ontbreekt; wijk kon niet worden vastgelegd.')
          return
        end
        local street = type(result.streets) == 'table' and #result.streets == 1 and result.streets[1] or nil
        if not manual or not street or not street.house or name == 'Heel Zwolle' then
          callback('restart')
          return
        end
        vim.system({
          commands.bin('pubble-wijk'), 'onthoud',
          '--street', street.name, '--house', street.house, '--choice', name,
        }, { text = true }, function(saved)
          vim.schedule(function()
            if saved.code ~= 0 then
              vim.notify('Wijk gekozen, maar adres kon niet worden onthouden: ' .. vim.trim(saved.stderr or ''), vim.log.levels.WARN)
            end
            callback('restart')
          end)
        end)
      end

      if result.status == 'suggested' and type(result.suggested) == 'string' then
        local evidence = type(result.evidence) == 'table' and result.evidence[1] or nil
        vim.notify('Wijk voorgesteld: ' .. result.suggested .. (evidence and (' — ' .. evidence) or ''), vim.log.levels.INFO)
        apply(result.suggested, false)
        return
      end

      local options = {}
      for _, choice in ipairs(result.choices or {}) do
        if type(choice.name) == 'string' then table.insert(options, choice.name) end
      end
      if #options == 0 then callback('Geen Swollenaer-wijken beschikbaar.'); return end
      local prompt = 'Welke wijk hoort bij dit Swollenaer-bericht?'
      if type(result.evidence) == 'table' and result.evidence[1] then
        prompt = prompt .. '\nGevonden: ' .. result.evidence[1]
      end
      require('user_dialog').select(options, { prompt = prompt }, function(choice)
        if not choice then callback('Verzending geannuleerd: wijk nog niet gekozen.'); return end
        apply(choice, true)
      end)
    end)
  end)
end

return M
