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

-- Alleen weergave van het Pythonrapport; woorddiff verandert geen validatie.
local function word_marks(buf, row, prefix, text, spans, group)
  local words, positions = {}, {}
  for pos, word in text:gmatch('()(%S+)') do
    words[#words + 1], positions[#positions + 1] = word, pos - 1
  end
  for _, span in ipairs(spans) do
    local first, count = span[1], span[2]
    if count > 0 and positions[first] then
      local last = first + count - 1
      vim.api.nvim_buf_set_extmark(buf, ns, row, #prefix + positions[first], {
        end_col = #prefix + positions[last] + #words[last], hl_group = group, priority = 180,
      })
    end
  end
end

local function render_panel(session)
  if not session.panel or not vim.api.nvim_buf_is_valid(session.panel) then return end
  local report = session.quote_report
  local differences = report.quote_differences
  local difference = differences[session.quote_index]
  local lines = {
    session.status or 'Wacht op correctie: het voorstel is nog niet overgenomen.',
    '<leader>aY: opnieuw controleren + indien geldig overnemen | q: bron behouden | ]q/[q: volgend/vorig citaat',
    'Herstel rechts. Overzicht scrollen: Ctrl-w k, daarna j/k; terug naar voorstel: Ctrl-w p.',
  }
  local source, proposal
  if difference then
    lines[#lines + 1] = ('Citaat %d van %d · %d mogelijke bronpassage(s) · kleuren tonen woordverschillen, geen automatische correctie')
      :format(session.quote_index, #differences, #difference.source_candidates)
    source = difference.source_candidates[1] and difference.source_candidates[1].text
    proposal = difference.proposal.text
    lines[#lines + 1] = 'Bron:     ' .. (source or '(geen vergelijkbaar broncitaat gevonden)')
    lines[#lines + 1] = 'Voorstel: ' .. proposal
    if #difference.source_candidates > 1 then
      lines[#lines + 1] = 'Andere mogelijke bron: ' .. difference.source_candidates[2].text
    end
  else
    lines[#lines + 1] = 'Geen afzonderlijke citaatpassage gevonden. Controlepunten:'
    for _, issue in ipairs(report.issues) do lines[#lines + 1] = issue.message:gsub('\n', ' ') end
  end
  vim.bo[session.panel].modifiable = true
  vim.api.nvim_buf_set_lines(session.panel, 0, -1, false, lines)
  vim.bo[session.panel].modifiable = false
  vim.api.nvim_buf_clear_namespace(session.panel, ns, 0, -1)
  if source and proposal then
    local function tokens(text)
      local words = {}; for word in text:gmatch('%S+') do words[#words + 1] = word end
      return table.concat(words, '\n') .. '\n'
    end
    local changes = vim.diff(tokens(source), tokens(proposal), { result_type = 'indices' })
    local removed, added = {}, {}
    for _, change in ipairs(changes) do
      removed[#removed + 1] = { change[1], change[2] }
      added[#added + 1] = { change[3], change[4] }
    end
    word_marks(session.panel, 4, 'Bron:     ', source, removed, 'DiffDelete')
    word_marks(session.panel, 5, 'Voorstel: ', proposal, added, 'DiffAdd')
  end
  if vim.api.nvim_win_is_valid(session.panel_win) then
    vim.wo[session.panel_win].winbar = ' Citaatcontrole · nog niets overgenomen'
    local rows = 0
    local width = math.max(1, vim.api.nvim_win_get_width(session.panel_win))
    for _, line in ipairs(lines) do rows = rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width)) end
    vim.api.nvim_win_set_height(session.panel_win, math.min(rows, math.max(4, math.floor(vim.o.lines / 2))))
  end
end

local function focus_quote(session, index)
  local differences = session.quote_report.quote_differences
  if #differences == 0 then render_panel(session); return end
  session.quote_index = ((index - 1) % #differences) + 1
  local difference = differences[session.quote_index]
  local candidate = difference.source_candidates[1]
  local function jump(win, buf, passage)
    if not passage or not vim.api.nvim_win_is_valid(win) then return end
    -- Na eigen edits kunnen rapportregels verouderd zijn; hercontrole vernieuwt ze.
    local line = math.min(passage.start_line, vim.api.nvim_buf_line_count(buf))
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    vim.api.nvim_win_call(win, function() vim.cmd('normal! zvzt') end)
  end
  jump(session.original_win, session.original, candidate)
  jump(session.proposal_win, session.proposal, difference.proposal)
  render_panel(session)
end

local function decorate(session, report)
  session.quote_report, session.quote_index = report, 1
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
  for index, difference in ipairs(report.quote_differences) do
    mark(session.proposal, difference.proposal, 'DiagnosticWarn', ' ← citaat ' .. index .. ': controleren')
    for _, candidate in ipairs(difference.source_candidates) do
      mark(session.original, candidate, 'DiagnosticInfo', ' ← mogelijke bron voor citaat ' .. index)
    end
  end
  for _, buf in ipairs(session.buffers) do
    vim.keymap.set('n', ']q', function() focus_quote(session, session.quote_index + 1) end,
      { buffer = buf, desc = 'Volgend afwijkend citaat' })
    vim.keymap.set('n', '[q', function() focus_quote(session, session.quote_index - 1) end,
      { buffer = buf, desc = 'Vorig afwijkend citaat' })
  end
  focus_quote(session, 1)
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
    compact = true, review_panel = true, status = render_panel, decorate = decorate, is_current = item.is_current,
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
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = session.proposal, callback = function()
      if session.closed then return end
      session.set_status('Voorstel gewijzigd: het overzicht toont de vorige controle. <leader>aY vernieuwt de vergelijking en controleert opnieuw.')
    end,
  })
  queue.session = session
  notify.workflow('Citaatcontrole wacht op correctie. Boven staan status en woordverschillen; herstel rechts. <leader>aY controleert opnieuw en neemt alleen bij een geslaagde controle over. q behoudt de bron.',
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
