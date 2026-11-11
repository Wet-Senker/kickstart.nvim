-- Open een geordende reeks URL's zonder een race tussen losse macOS-processen.

local M = {}
local notifications = require('texttools_notify')

local function notify_error(detail)
  notifications.schedule(function()
    notifications.notify('Browserlinks openen mislukt: ' .. vim.trim(tostring(detail or 'onbekende fout')),
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
    local ok, process_or_error = pcall(notifications.system, command, { text = true }, function(result)
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
    if urls[index] then notifications.defer_fn(open_next, opts.delay_ms or 200) end
  end
  open_next()
  return true
end

-- Sluit uitsluitend het tijdelijke loopbacktabblad dat bij deze workflow
-- hoort en geef daarna iTerm weer focus. Browser- en applicatienamen blijven
-- hier in de macOS-presentatieadapter; de fotokeuze zelf kent ze niet.
function M.finish_temporary_tab(url, opts)
  opts = opts or {}
  if type(url) ~= 'string' or not url:match('^http://127%.0%.0%.1:%d+/[%w_-]+/$') then return false end
  local is_macos = opts.is_macos
  if is_macos == nil then is_macos = vim.fn.has 'mac' == 1 end
  if not is_macos then return true end
  local script = [[
function run(argv) {
  var target = argv[0];
  var names = ['Safari', 'Google Chrome', 'Brave Browser', 'Microsoft Edge', 'Chromium', 'Arc'];
  for (var i = 0; i < names.length; i++) {
    try {
      var app = Application(names[i]);
      if (!app.running()) continue;
      var windows = app.windows();
      for (var w = 0; w < windows.length; w++) {
        var tabs = windows[w].tabs();
        for (var t = 0; t < tabs.length; t++) {
          var current = '';
          try { current = String(tabs[t].url()); } catch (_) {}
          if (current === target || current.indexOf(target) === 0) {
            try { tabs[t].close(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
  try { Application('iTerm').activate(); } catch (_) {}
}
]]
  local command = { '/usr/bin/osascript', '-l', 'JavaScript', '-e', script, url }
  local ok, process_or_error = pcall(notifications.system, command, { text = true }, function(result)
    if result.code ~= 0 then notify_error(result.stderr or result.stdout) end
  end)
  if not ok or not process_or_error then
    notify_error(process_or_error)
    return false
  end
  return true
end

return M
