-- Start Quicktemplate Advanced als lokale, alleen-lezen browsersessie.
local M = {}
local browser = require 'ordered_browser'
local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local session

local function notify(message, level)
  notifications.workflow(message, level or vim.log.levels.INFO)
end

local function open_url(url)
  if not browser.open_urls({ url }) then
    notify('Quicktemplate kon niet in de browser worden geopend.', vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.open()
  if session and session.url then
    open_url(session.url)
    return
  end
  if session then
    notify('Quicktemplate wordt al gestart.')
    return
  end

  local root = vim.env.QUICKTEMPLATE_ROOT or vim.fn.expand '~/workspace/quicktemplate'
  local script = root .. '/tools/quicktemplate_server.py'
  if vim.fn.filereadable(script) ~= 1 then
    notify('Quicktemplate ontbreekt in ~/workspace/quicktemplate.', vim.log.levels.ERROR)
    return
  end

  local current = { pending = '', url = nil, ready = false }
  session = current
  local ok, process = pcall(vim.system, { commands.bin 'python', script }, {
    text = true,
    stdout = function(err, chunk)
      if err or not chunk or session ~= current then return end
      current.pending = current.pending .. chunk
      while current.pending:find('\n', 1, true) do
        local ending = current.pending:find('\n', 1, true)
        local line = current.pending:sub(1, ending - 1)
        current.pending = current.pending:sub(ending + 1)
        local decoded, event = pcall(vim.json.decode, line)
        if decoded and type(event) == 'table' and event.version == 1 then
          vim.schedule(function()
            if session ~= current then return end
            if event.event == 'ready' and type(event.url) == 'string'
                and event.url:match '^http://127%.0%.0%.1:%d+/[%w_-]+/advanced$' then
              current.ready = true
              current.url = event.url
              open_url(event.url)
            elseif event.event == 'error' then
              notify(event.message or 'Quicktemplate kon niet starten.', vim.log.levels.ERROR)
            end
          end)
        end
      end
    end,
  }, function(result)
    vim.schedule(function()
      if session ~= current then return end
      session = nil
      if not current.ready and result.code ~= 0 then
        notify('Quicktemplate kon niet starten. Controleer de Pubble-Sleutelhanger.', vim.log.levels.ERROR)
      end
    end)
  end)
  if not ok then
    session = nil
    notify('Quicktemplate kon niet worden gestart.', vim.log.levels.ERROR)
    return
  end
  current.process = process
end

return M
