local M = {}
local ns = vim.api.nvim_create_namespace('AgendaDuplicateDisplay')
local folds = {}

function M.show(buf, skipped)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if skipped ~= true then
    for win, bounds in pairs(folds[buf] or {}) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_win_call(win, function()
          if vim.wo.foldmethod == 'manual' and vim.fn.foldclosed(bounds[1]) == bounds[1]
              and vim.fn.foldclosedend(bounds[1]) == bounds[2] then
            local view = vim.fn.winsaveview()
            vim.cmd(('silent %dnormal! zd'):format(bounds[1]))
            vim.fn.winrestview(view)
          end
        end)
      end
    end
    folds[buf] = nil
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local article, first, last
  for index, line in ipairs(lines) do
    if line == '=== ARTIKEL ===' then article = index end
    if line == '## Kalender' then
      first, last = index, #lines
    elseif first and line:match('^##%s') then
      last = index - 1
      break
    end
  end
  if article then
    vim.api.nvim_buf_set_extmark(buf, ns, article - 1, 0, {
      virt_lines = { { { 'Agenda overgeslagen wegens doublure', 'DiagnosticInfo' } } },
      virt_lines_above = true,
    })
  end
  if not first or last <= first then return end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      if vim.wo.foldmethod ~= 'manual' or not vim.wo.foldenable then return end
      if vim.fn.foldlevel(first) ~= 0 or vim.fn.foldlevel(last) ~= 0 then return end
      local view = vim.fn.winsaveview()
      vim.cmd(('silent %d,%dfold'):format(first, last))
      folds[buf] = folds[buf] or {}
      folds[buf][win] = { first, last }
      vim.fn.winrestview(view)
    end)
  end
end

vim.api.nvim_create_autocmd('BufWipeout', {
  callback = function(event) folds[event.buf] = nil end,
})

return M
