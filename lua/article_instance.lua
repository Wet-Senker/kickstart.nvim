-- Proceslokale presentatie en afsluitbewaking. Publicatie- en herstelstate
-- blijven eigendom van de bestaande Python-/artikelworkflows.
local M = {}
local notifications = require('texttools_notify')
local warning = 'Dit artikel heeft nog een lopende taak of vraag. Wacht op afronding, '
  .. 'beantwoord de vraag of annuleer de bewerking met <leader>aq. Publicatie eerst laten afronden. '
  .. 'Alleen bewust afbreken: :TexttoolsSluiten!'

function M.pending()
  local jobs = package.loaded.buffer_jobs
  local activity = package.loaded.article_activity
  local dialog = package.loaded.user_dialog
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.b[buf].publication_in_progress == true
        or (jobs and jobs.count(buf) > 0)
        or (dialog and dialog.has_question(buf))
        or (activity and activity.has_tasks(buf)) then
      return true
    end
  end
  return false
end

function M.close(command, force)
  if not force and M.pending() then
    notifications.notify(warning, vim.log.levels.WARN)
    return false
  end
  vim.cmd(command)
  return true
end

local function exits(command)
  local name = command:match('^%s*(%a+)')
  if not name then return false end
  local all = name == 'qa' or name == 'qal' or name == 'qall'
    or name == 'wqa' or name == 'wqal' or name == 'wqall'
    or name == 'xa' or name == 'xal' or name == 'xall'
  if all then return true end
  if name ~= 'q' and name ~= 'qu' and name ~= 'qui' and name ~= 'quit'
      and name ~= 'wq' and name ~= 'x' and name ~= 'xi' and name ~= 'xit'
      and name ~= 'exi' and name ~= 'exit' then return false end
  if vim.api.nvim_win_get_config(0).relative ~= '' then return false end
  local count = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == '' then count = count + 1 end
  end
  return count == 1
end

function M.setup()
  if vim.env.TEXTTOOLS_ARTICLE_INSTANCE ~= '1' then return false end
  local title = vim.env.TEXTTOOLS_ARTICLE_TITLE or 'Texttools · Artikel'
  title = title:gsub('%c', ' '):gsub('%%', '%%%%')
  vim.o.title, vim.o.titlestring = true, title
  local group = vim.api.nvim_create_augroup('TexttoolsArticleInstance', { clear = true })
  -- ExitPre-fouten verhinderen afsluiten niet. Onderschep daarom de gewone
  -- getypte afsluitopdracht vóór uitvoering; geen blokkerende bevestigingslus.
  vim.api.nvim_create_autocmd('CmdlineLeave', { group = group, callback = function()
    if vim.fn.getcmdtype() == ':' and not vim.v.event.abort
        and exits(vim.fn.getcmdline()) and M.pending() then
      vim.cmd('let v:event.abort = v:true')
      vim.schedule(function() notifications.notify(warning, vim.log.levels.WARN) end)
    end
  end })
  vim.api.nvim_create_user_command('TexttoolsSluiten', function(opts)
    M.close(opts.bang and 'qa!' or 'qa', opts.bang)
  end, { bang = true, force = true, desc = 'Artikel sluiten; ! breekt ook taken en onopgeslagen werk af' })
  vim.keymap.set('n', 'ZZ', function() M.close('wq') end, { desc = 'Opslaan en sluiten als taken klaar zijn' })
  vim.keymap.set('n', 'ZQ', function() M.close('q!') end, { desc = 'Sluiten als taken klaar zijn' })
  return true
end

return M
