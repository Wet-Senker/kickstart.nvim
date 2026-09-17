local M = {}

local function log_path()
  local directory = vim.env.TEXTTOOLS_LOG_DIR
  if type(directory) ~= 'string' or directory == '' then
    directory = vim.fn.expand('~/.texttools')
  end
  return directory .. '/pubble.log'
end
M.log_path = log_path

local function timestamp()
  local seconds, microseconds = vim.uv.gettimeofday()
  return os.date('!%Y-%m-%dT%H:%M:%S', seconds)
    .. string.format('.%03d+00:00', math.floor(microseconds / 1000))
end

local serial = 0
local function identifier(prefix, buf)
  serial = serial + 1
  return table.concat({
    prefix,
    tostring(vim.fn.getpid()),
    tostring(buf or 0),
    tostring(vim.uv.hrtime()),
    tostring(serial),
  }, '-')
end

local function append(entry)
  local ok = pcall(function()
    local path = log_path()
    vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
    local handle = assert(io.open(path, 'a'))
    handle:write(vim.json.encode(entry), '\n')
    handle:close()
  end)
  return ok
end
M._append = append

local function valid_buffer(buf)
  return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf)
end

function M.workflow_id(buf)
  if not valid_buffer(buf) then return identifier('nvim-workflow', 0) end
  local existing = vim.b[buf].texttools_workflow_id
  if type(existing) == 'string' and existing ~= '' then return existing end
  local created = identifier('nvim-workflow', buf)
  vim.b[buf].texttools_workflow_id = created
  return created
end

local function source_for(buf)
  if not valid_buffer(buf) then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' then return nil end
  return vim.fn.resolve(vim.fn.fnamemodify(name, ':p'))
end

function M.start(buf, action, detail)
  local workflow_id = M.workflow_id(buf)
  local token = {
    action = tostring(action or 'Handeling'),
    action_id = identifier('nvim-action', buf),
    workflow_id = workflow_id,
    source = source_for(buf),
    started_ns = vim.uv.hrtime(),
  }
  append {
    ts = timestamp(),
    kind = 'workflow',
    event = 'action_started',
    client = 'nvim',
    run_id = workflow_id,
    workflow_id = workflow_id,
    source = token.source,
    action = token.action,
    action_id = token.action_id,
    detail = detail,
  }
  return token
end

function M.finish(token, outcome, detail)
  if type(token) ~= 'table' or token.finished then return end
  token.finished = true
  append {
    ts = timestamp(),
    kind = 'workflow',
    event = 'action_finished',
    client = 'nvim',
    run_id = token.workflow_id,
    workflow_id = token.workflow_id,
    source = token.source,
    action = token.action,
    action_id = token.action_id,
    outcome = outcome or 'unknown',
    duration_ms = math.max(0, math.floor((vim.uv.hrtime() - token.started_ns) / 1e6 + 0.5)),
    detail = detail,
  }
end

function M.environment(token)
  if type(token) ~= 'table' then return {} end
  return {
    TEXTTOOLS_RUN_ID = token.workflow_id,
    TEXTTOOLS_RUN_COMMAND = token.action,
    TEXTTOOLS_RUN_SOURCE = token.source or '',
  }
end

function M.with_environment(options, token)
  local result = vim.deepcopy(options or {})
  result.env = vim.tbl_extend('force', result.env or {}, M.environment(token))
  return result
end

local function open_summary(text)
  local lines = vim.split(vim.trim(text or ''), '\n', { plain = true })
  if #lines == 0 or (#lines == 1 and lines[1] == '') then
    lines = { 'Het Texttools-logboek bevat geen leesbare tijdlijn.' }
  end
  vim.cmd('botright 16new')
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'text'
  vim.bo[buf].modifiable = false
  vim.keymap.set('n', 'q', '<cmd>close<cr>', {
    buffer = buf,
    silent = true,
    desc = 'Texttools-logboek sluiten',
  })
end

function M.show(options)
  options = options or {}
  local source_buf = options.buf or vim.api.nvim_get_current_buf()
  local command = {
    require('texttools_commands').bin('python'),
    '-m',
    'texttools.execution_log_cli',
    '--limit',
    tostring(options.limit or 80),
  }
  local workflow_id = valid_buffer(source_buf)
      and vim.b[source_buf].texttools_workflow_id
      or nil
  if not options.latest and type(workflow_id) == 'string' and workflow_id ~= '' then
    vim.list_extend(command, { '--id', workflow_id })
  end

  local function run(current, allow_fallback)
    vim.system(current, { text = true }, function(result)
      if result.code ~= 0 and allow_fallback then
        run({
          require('texttools_commands').bin('python'),
          '-m',
          'texttools.execution_log_cli',
          '--limit',
          tostring(options.limit or 80),
        }, false)
        return
      end
      vim.schedule(function()
        local output = result.code == 0 and result.stdout or result.stderr
        open_summary(output ~= '' and output or 'Het Texttools-logboek kon niet worden gelezen.')
      end)
    end)
  end
  run(command, workflow_id ~= nil and not options.latest)
end

function M.setup()
  vim.api.nvim_create_user_command('TexttoolsLog', function(command)
    M.show { latest = command.bang }
  end, {
    bang = true,
    desc = 'Toon de veilige Texttools-tijdlijn (! = laatste workflow)',
    force = true,
  })
end

return M
