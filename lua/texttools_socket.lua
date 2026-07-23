local M = {}

local function connect(api, socket_path)
  local ok, channel = pcall(api.fn.sockconnect, "pipe", socket_path, { rpc = true })
  if not ok or type(channel) ~= "number" or channel <= 0 then return nil end
  return channel
end

local function close_channel(api, channel)
  pcall(api.fn.chanclose, channel)
end

---Ensure that this Neovim instance owns the configured server socket.
---
---A failed first connect is checked once more immediately before cleanup. This
---protects a socket that another Neovim instance reclaimed between the initial
---serverstart/connect attempts.
---@param socket_path string
---@param api? table Injectable vim facade for the headless regression tests.
---@return "started"|"live"|"reclaimed"|"unavailable" status
---@return string? address
function M.ensure(socket_path, api)
  api = api or vim

  local started, address = pcall(api.fn.serverstart, socket_path)
  if started and address ~= "" then return "started", address end

  local channel = connect(api, socket_path)
  if channel then
    close_channel(api, channel)
    return "live", socket_path
  end

  if api.fn.getftype(socket_path) ~= "socket" then return "unavailable", nil end

  -- Race guard: another process may have replaced/reclaimed the stale path
  -- since the first failed probe. A live replacement must never be unlinked.
  channel = connect(api, socket_path)
  if channel then
    close_channel(api, channel)
    return "live", socket_path
  end
  if api.fn.getftype(socket_path) ~= "socket" then return "unavailable", nil end

  if api.fn.delete(socket_path) ~= 0 then return "unavailable", nil end

  local reclaimed, reclaimed_address = pcall(api.fn.serverstart, socket_path)
  if reclaimed and reclaimed_address ~= "" then
    return "reclaimed", reclaimed_address
  end
  return "unavailable", nil
end

return M
