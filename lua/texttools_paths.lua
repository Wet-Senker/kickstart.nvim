local M = {}

---Return the shared Pubble Inbox path.
---TEXTTOOLS_INBOX_DIR can override the stable local symlink when needed.
function M.inbox()
  local configured = vim.env.TEXTTOOLS_INBOX_DIR
  if configured and configured ~= '' then
    return vim.fn.expand(configured)
  end
  return vim.fn.expand('~/.texttools/pubble-inbox')
end

---Return the work folder for articles imported manually through `pv`.
function M.work()
  return M.inbox() .. '/werk'
end

return M
