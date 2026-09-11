-- Open een geordende reeks URL's zonder een race tussen losse macOS-processen.

local M = {}

local function notify_error(detail)
  vim.schedule(function()
    vim.notify('Browserlinks openen mislukt: ' .. vim.trim(tostring(detail or 'onbekende fout')),
      vim.log.levels.WARN)
  end)
end

function M.open_urls(urls, opts)
  opts = opts or {}
  if type(urls) ~= 'table' or #urls == 0 then return true end

  local is_macos = opts.is_macos
  if is_macos == nil then is_macos = vim.fn.has 'mac' == 1 end
  if is_macos then
    local command = { '/usr/bin/open', '-g' }
    vim.list_extend(command, urls)
    local ok, process_or_error = pcall(vim.system, command, { text = true }, function(result)
      if result.code ~= 0 then notify_error(result.stderr or result.stdout) end
    end)
    if not ok or not process_or_error then
      notify_error(process_or_error)
      return false
    end
    return true
  end

  -- Niet-macOS heeft geen portable multi-URL-opener. Start daar een
  -- niet-blokkerende wachtrij, zodat de standaardhandler de volgorde behoudt.
  local index = 1
  local function open_next()
    local url = urls[index]
    if not url then return end
    local ok, result, err = pcall(vim.ui.open, url)
    if not ok then
      notify_error(result)
    elseif err then
      notify_error(err)
    end
    index = index + 1
    if urls[index] then vim.defer_fn(open_next, opts.delay_ms or 200) end
  end
  open_next()
  return true
end

return M
