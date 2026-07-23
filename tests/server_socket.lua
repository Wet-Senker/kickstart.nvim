local socket = require("texttools_socket")

local function fake_api(options)
  local state = {
    deleted = 0,
    closed = {},
    connect_calls = 0,
    start_calls = 0,
  }
  local api = { fn = {} }

  function api.fn.serverstart(path)
    state.start_calls = state.start_calls + 1
    local result = options.serverstart[state.start_calls]
    if type(result) == "table" and result.error then error(result.error) end
    return result
  end

  function api.fn.sockconnect()
    state.connect_calls = state.connect_calls + 1
    local result = options.sockconnect[state.connect_calls]
    if type(result) == "table" and result.error then error(result.error) end
    return result
  end

  function api.fn.getftype()
    if type(options.filetype) == "table" then
      return options.filetype[state.connect_calls]
    end
    return options.filetype
  end

  function api.fn.chanclose(channel)
    table.insert(state.closed, channel)
    return 0
  end

  function api.fn.delete()
    state.deleted = state.deleted + 1
    return options.delete_result or 0
  end

  return api, state
end

local live_api, live = fake_api({
  serverstart = { { error = "address already in use" } },
  sockconnect = { 41 },
  filetype = "socket",
})
local live_status = socket.ensure("/tmp/main.sock", live_api)
assert(live_status == "live", "levende socket werd niet herkend")
assert(live.deleted == 0, "levende socket werd verwijderd")
assert(live.closed[1] == 41, "probechannel van levende socket bleef open")

local stale_api, stale = fake_api({
  serverstart = {
    { error = "stale address" },
    "/tmp/main.sock",
  },
  sockconnect = {
    { error = "connection refused" },
    { error = "connection refused" },
  },
  filetype = "socket",
})
local stale_status = socket.ensure("/tmp/main.sock", stale_api)
assert(stale_status == "reclaimed", "dode socket werd niet veilig hergebruikt")
assert(stale.deleted == 1, "dode socket werd niet eenmaal verwijderd")
assert(stale.start_calls == 2, "serverstart werd na stale cleanup niet herhaald")

local reused_api, reused = fake_api({
  serverstart = { { error = "address already in use" } },
  sockconnect = {
    { error = "connection refused" },
    77,
  },
  filetype = "socket",
})
local reused_status = socket.ensure("/tmp/main.sock", reused_api)
assert(reused_status == "live", "opnieuw gebruikte socket werd niet herkend")
assert(reused.deleted == 0, "opnieuw gebruikte levende socket werd verwijderd")
assert(reused.closed[1] == 77, "probechannel van hergebruikte socket bleef open")

local file_api, file_state = fake_api({
  serverstart = { { error = "address unavailable" } },
  sockconnect = { { error = "connection refused" } },
  filetype = "file",
})
local file_status = socket.ensure("/tmp/main.sock", file_api)
assert(file_status == "unavailable", "niet-socketbestand kreeg verkeerde status")
assert(file_state.deleted == 0, "niet-socketbestand werd verwijderd")

print("server socket: OK")
