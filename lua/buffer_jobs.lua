-- Alleen actuele editororchestratie, geen publicatie- of domeinstate.
-- Elke taak kan uitsluitend haar eigen token afronden. pending_jobs blijft
-- een compatibele afgeleide teller, nooit de autoriteit voor verzending.
local M = {}
local states, serial = {}, 0

local function valid(buf) return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf) end

function M.start(buf, action)
  if not valid(buf) then return nil end
  serial = serial + 1
  local token = { buf = buf, id = serial, action = action or 'Artikelbewerking' }
  local state = states[buf] or { count = 0, tasks = {} }
  states[buf] = state
  state.tasks[token.id] = token
  state.count = state.count + 1
  vim.b[buf].pending_jobs = state.count
  return token
end

function M.finish(token)
  if type(token) ~= 'table' or token.finished then return false end
  local state = states[token.buf]
  if not state or state.tasks[token.id] ~= token then return false end
  token.finished = true
  state.tasks[token.id] = nil
  state.count = state.count - 1
  if valid(token.buf) then vim.b[token.buf].pending_jobs = state.count end
  return true
end

function M.count(buf)
  local state = states[buf]
  return state and state.count or 0
end

function M.active(buf)
  local result = {}
  for _, token in pairs((states[buf] or {}).tasks or {}) do
    result[#result + 1] = { id = token.id, action = token.action }
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

vim.api.nvim_create_autocmd('BufWipeout', {
  callback = function(event) states[event.buf] = nil end,
})

return M
