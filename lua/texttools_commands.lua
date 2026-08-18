local M = {}

function M.root()
  local configured = vim.env.TEXTTOOLS_ROOT
  if configured and configured ~= '' then
    return vim.fn.expand(configured)
  end
  return vim.fn.expand('~/workspace/texttools')
end

function M.path(...)
  return vim.fs.joinpath(M.root(), ...)
end

function M.bin(name)
  return M.path('.venv', 'bin', name)
end

return M
