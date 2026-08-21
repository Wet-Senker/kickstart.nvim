local M = {}

-- Workflowmeldingen zijn informatief: ze mogen de editor nooit onderbreken
-- met Neovims hit-enter-prompt. Fidget toont ze als tijdelijke toast. De
-- fallback houdt de configuratie ook bruikbaar wanneer Fidget niet geladen is.
function M.workflow(message, level, options)
  options = options or {}
  level = level or vim.log.levels.INFO

  local ok, notification = pcall(require, "fidget.notification")
  if ok and type(notification.notify) == "function" then
    notification.notify(message, level, {
      annote = options.annote or "Texttools",
      ttl = options.ttl or 6,
    })
    return
  end

  vim.notify(message, level)
end

return M
