local M = {}
local activity = require 'article_activity'
local context
local serial = 0
local function pack(...) return { n = select('#', ...), ... } end

function M.source_buffer()
  return context and context.buf or activity.source(vim.api.nvim_get_current_buf())
    or vim.api.nvim_get_current_buf()
end

function M.task_scope()
  local scope = context and context.scope
  if scope then return { buf = context.buf, id = scope.id, action = scope.action } end
end

function M.defer_result(scope, waiting_text)
  if scope then activity.defer_result(scope.buf, scope.id, waiting_text) end
end

function M.task_result(outcome, scope)
  scope = scope or M.task_scope()
  if scope then activity.result(scope.buf, scope.id, outcome) end
end

-- Leg de bron vast vóór een asynchrone grens. Ook een inmiddels gesloten bron
-- blijft expliciet: een late melding hoort nooit bij een ander artikel.
function M.bind(buf, callback, scope)
  local owner = buf
  if owner == nil then owner = context and context.buf or (not context and (activity.current_source() or vim.api.nvim_get_current_buf()) or nil) end
  local captured_scope = context and context.buf == owner and context.scope or nil
  return function(...)
    local previous = context
    context = { buf = owner, scope = scope or (previous and previous.buf == owner and previous.scope) or captured_scope }
    local dialogs = package.loaded['user_dialog']
    local result = pack(pcall(dialogs and not vim.in_fast_event() and dialogs.run or function(fn, ...) return fn(...) end,
      callback, ...))
    context = previous
    if not result[1] then error(result[2], 0) end
    return unpack(result, 2, result.n)
  end
end

function M.schedule(callback) vim.schedule(M.bind(nil, callback, context and context.scope)) end

function M.schedule_wrap(callback)
  local wrapped = M.bind(nil, callback, context and context.scope)
  return function(...)
    local arguments = { n = select('#', ...), ... }
    vim.schedule(function() wrapped(unpack(arguments, 1, arguments.n)) end)
  end
end

function M.defer_fn(callback, milliseconds) return vim.defer_fn(M.bind(nil, callback, context and context.scope), milliseconds) end

function M.system(command, options, callback)
  options = vim.tbl_extend('force', {}, options or {})
  local scope = options.texttools_activity
  local await_result = scope and scope.await_result
  options.texttools_activity = nil -- UI-contract, geen vim.system/Python-optie.
  local owner = scope and scope.buf or (context and context.buf)
    or (not context and (activity.current_source() or vim.api.nvim_get_current_buf()) or nil)
  local automatic = callback and owner and not (scope and scope.tracked)
  if automatic then
    serial = serial + 1
    scope = {
      action = scope and scope.action or vim.fn.fnamemodify(tostring(command[1] or 'Achtergrondtaak'), ':t'),
      id = 'process-' .. serial,
      buf = owner,
    }
    activity.start(owner, scope.id, scope.action)
    if await_result then activity.defer_result(owner, scope.id) end
  end
  local bound = callback and M.bind(owner, function(result)
    if automatic then activity.finish(owner, scope.id) end
    callback(result)
  end, scope) or nil
  if options and (type(options.stdout) == 'function' or type(options.stderr) == 'function') then
    options = vim.tbl_extend('force', {}, options)
    for _, key in ipairs { 'stdout', 'stderr' } do
      if type(options[key]) == 'function' then options[key] = M.bind(owner, options[key], scope) end
    end
  end
  local started, process = pcall(vim.system, command, options, bound)
  if not started then
    if automatic then
      if await_result then activity.result(owner, scope.id, 'failed') end
      activity.finish(owner, scope.id)
      -- Alleen lokaal vastleggen. Callers behouden hun eigen foutafhandeling;
      -- buiten de strook geen extra, dubbele commandoregelmelding toevoegen.
      activity.record(owner, scope.action .. ' kon niet starten: ' .. tostring(process)
        .. ' Bekijk :TexttoolsLog en start de handeling opnieuw nadat de oorzaak is verholpen.',
        vim.log.levels.ERROR, { action = scope.action, run_id = scope.id })
    end
    error(process, 0)
  end
  return process
end

local function record(message, level, options)
  options = vim.tbl_extend('force', {}, options or {})
  if options.kind == 'progress' then return true end -- Register toont de lopende taak.
  if context and context.scope then
    if not options.action or options.action == context.scope.action then
      options.action = options.action or context.scope.action
      options.run_id = options.run_id or context.scope.id
    end
  end
  local buf = options.buf or (context and context.buf)
    or (not context and (activity.current_source() or vim.api.nvim_get_current_buf()) or nil)
  -- Een expliciete, gesloten bron wordt stil genegeerd; niet terugvallen op
  -- de huidige buffer of alsnog een globale fouttoast tonen.
  if context and context.buf and not vim.api.nvim_buf_is_valid(context.buf) then return true end
  if options.buf and not vim.api.nvim_buf_is_valid(options.buf) then return true end
  if buf then return activity.record(buf, message, level, options) end
  return false
end

function M.notify(message, level, options)
  if record(message, level, options) then return end
  vim.notify(message, level, options)
end

-- Eén resultaatroute voor alle Texttools-schermen. Fidget is uitsluitend voor
-- geregistreerd lopend werk. Vóór setup blijft Neovims eigen berichtenhistorie
-- de fallback; notify en workflow mogen nooit verschillend presenteren.
function M.workflow(message, level, options)
  return M.notify(message, level or vim.log.levels.INFO, options)
end

return M
