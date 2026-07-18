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

return M
