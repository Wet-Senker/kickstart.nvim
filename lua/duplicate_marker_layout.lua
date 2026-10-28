-- One-time transport for legacy header layout; the shared core owns the edit.
local M = {}
local notifications = require('texttools_notify')

function M.normalize(buf, done, attempt)
  if not vim.api.nvim_buf_is_valid(buf) then done(false); return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local markdown = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  local function complete(result)
    notifications.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then done(false); return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        if (attempt or 0) < 1 then M.normalize(buf, done, 1) else done(false) end
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(data) ~= 'table' or data.version ~= 1
          or type(data.markdown) ~= 'string' then
        done(false)
        return -- Formatting must not turn a read-only inspection into a workflow error.
      end
      if data.changed and vim.bo[buf].modifiable and not vim.bo[buf].readonly then
        require('article_notices').replace_content(buf, vim.split(data.markdown, '\n', { plain = true }))
      end
      done(true)
    end)
  end
  local ok = pcall(notifications.system, { require('texttools_commands').bin('python'),
    '-m', 'texttools.duplicate_selection' }, {
      text = true, stdin = vim.json.encode { action = 'normalize_marker', markdown = markdown },
      texttools_activity = { action = 'Technische gegevens ordenen', tracked = true, buf = buf },
    }, notifications.bind(buf, complete))
  if not ok then done(false) end
end

return M
