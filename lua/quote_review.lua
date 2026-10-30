-- Dunne client voor het Python-citaatrapport. Geen citaatmatching in Lua.
local M = {}
local notify = require('texttools_notify')
local review = require('editorial_review')
local queues = {}
local ns = vim.api.nvim_create_namespace('texttools_quote_review')
M.namespace = ns

local function valid(report, source)
  if not review.valid_report(report, source) or report.kind ~= 'quote_review'
      or type(report.quote_differences) ~= 'table' or not vim.islist(report.quote_differences) then return false end
  local function passage(item)
    return type(item) == 'table' and type(item.text) == 'string' and type(item.start_line) == 'number'
      and item.start_line >= 1 and item.start_line % 1 == 0 and type(item.end_line) == 'number'
      and item.end_line >= item.start_line and item.end_line % 1 == 0
  end
  for _, difference in ipairs(report.quote_differences) do
    if not passage(difference.proposal) or type(difference.source_candidates) ~= 'table'
        or not vim.islist(difference.source_candidates) then return false end
    for _, item in ipairs(difference.source_candidates) do if not passage(item) then return false end end
  end
  return true
end
M.valid_report = valid

local function decorate(session, report)
  vim.api.nvim_buf_clear_namespace(session.original, ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(session.proposal, ns, 0, -1)
  local function mark(buf, item, hl, note)
    local count = vim.api.nvim_buf_line_count(buf)
    if item.start_line > count or item.end_line > count then return end
    vim.api.nvim_buf_set_extmark(buf, ns, item.start_line - 1, 0, {
      end_row = item.end_line, end_col = 0, line_hl_group = hl, priority = 160,
      virt_text = { { note, hl } }, virt_text_pos = 'eol',
    })
  end
  for _, difference in ipairs(report.quote_differences) do
    mark(session.proposal, difference.proposal, 'DiagnosticWarn', ' ← citaat controleren')
    for _, candidate in ipairs(difference.source_candidates) do
      mark(session.original, candidate, 'DiagnosticInfo', ' ← vergelijkbaar broncitaat')
    end
  end
  local first = report.quote_differences[1]
  if first then
    local candidate = first.source_candidates[1]
    if candidate then vim.api.nvim_win_set_cursor(session.windows[1], { candidate.start_line, 0 }) end
    vim.api.nvim_win_set_cursor(session.windows[2], { first.proposal.start_line, 0 })
  end
end

local function next_review(buf)
  local queue = queues[buf]
  if not queue or queue.active then return end
  local item = table.remove(queue, 1)
  if not item then
    queues[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].texttools_pending_quote_review = nil end
    return
  end
  if not item.is_current() then
    item.fail('Citaatvoorstel vervallen doordat de bron is gewijzigd. Start de bewerking opnieuw.')
    vim.schedule(function() next_review(buf) end)
    return
  end
  queue.active = true
  local function finish()
    queue.active = nil
    if vim.api.nvim_buf_is_valid(buf) then
      vim.b[buf].texttools_pending_quote_review = #queue > 0 or nil
      notify.workflow('Citaatvergelijking gesloten.', vim.log.levels.INFO,
        { buf = buf, action = 'Citaat beoordelen', notice_key = 'quote-review', resolved = true, detail = true })
    end
    vim.schedule(function() next_review(buf) end)
  end
  local session
  session = review.open({ source_buf = buf, original = vim.split(item.source, '\n', { plain = true }),
    report = item.report, label = item.label or 'AR', retry = item.retry or '<leader>ar',
    compact = true, decorate = decorate, is_current = item.is_current,
    validate = function(lines, done)
      local article = table.concat(lines, '\n')
      local started = pcall(notify.system, { require('texttools_commands').bin('python'), '-m', 'texttools.quote_review' },
        { text = true, stdin = vim.json.encode({ version = 1, source = item.source, article = article,
          source_sha256 = item.report.source_sha256 }),
          texttools_activity = { action = 'Artikel · Citaat opnieuw controleren', buf = buf } },
        function(result)
          notify.schedule(function()
            local ok, report = pcall(vim.json.decode, result.stdout or '')
            if result.code ~= 0 or not ok or not valid(report, item.source) or report.article ~= article then
              done(false, nil, 'Citaatcontrole kon niet afronden. Nog niets overgenomen; probeer <leader>aY opnieuw of behoud de bron met q.')
              return
            end
            done(report.status == 'ready', report)
          end)
        end)
      if not started then
        done(false, nil, 'De lokale citaatcontrole kon niet starten. Je tekst is behouden; probeer <leader>aY opnieuw of behoud de bron met q.')
      end
    end,
    on_accept = function(lines) item.ready(table.concat(lines, '\n')); finish() end,
    on_keep = function() item.fail('Citaatvoorstel niet overgenomen; oorspronkelijke tekst behouden.'); finish() end,
  })
  session.update = function(report) decorate(session, report) end
  queue.session = session
  notify.workflow('Citaat wijkt af: bron en voorstel staan naast elkaar. Herstel rechts; <leader>aY controleert en neemt over. q behoudt de bron.',
    vim.log.levels.WARN, { buf = buf, action = item.action or 'Citaat beoordelen', run_id = item.run_id,
      notice_key = 'quote-review', resolved = true, task_outcome = 'not_applied' })
end

function M.handle(result, options)
  if result.code ~= 3 then return false end
  local ok, report = pcall(vim.json.decode, result.stdout or '')
  if not ok or not valid(report, options.source) or report.status ~= 'needs_review' then
    options.fail('Ongeldig citaatvoorstel; bron behouden. Start de bewerking opnieuw.')
    return true
  end
  notify.task_result('attention')
  local queue = queues[options.buf] or {}
  local scope = notify.task_scope()
  queues[options.buf] = queue
  if vim.api.nvim_buf_is_valid(options.buf) then
    vim.b[options.buf].texttools_pending_quote_review = true
    vim.b[options.buf].send_requested = false
  end
  table.insert(queue, vim.tbl_extend('force', {}, options, { report = report,
    action = scope and scope.action, run_id = scope and scope.id }))
  next_review(options.buf)
  return true
end

function M.active(buf) return queues[buf] and queues[buf].session end
return M
