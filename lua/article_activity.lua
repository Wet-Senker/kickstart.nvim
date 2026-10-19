-- Alleen presentatie: artikeltekst, publicatiestate en het duurzame technische
-- logboek blijven eigendom van de bestaande workflows. Geen timer of polling.
local M = {}
local states, panels = {}, {}
local enabled, visible, expanded = false, true, false
local queued, drawing = false, false
local limit = 100
local preference_path
local refresh

local function valid(buf) return type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf) end

-- Volg expliciete relaties van hulp-/reviewbuffers, nooit een verdwenen bron
-- vervangen door het toevallig actieve artikel.
function M.source(buf)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not valid(buf) then return nil end
  local seen = {}
  for _ = 1, 8 do
    if not valid(buf) or seen[buf] then return nil end
    seen[buf] = true
    local next_buf = vim.b[buf].texttools_activity_source
      or vim.b[buf].user_dialog_source
      or vim.b[buf].pubble_photo_source
      or vim.b[buf].edition_source_buf
      or vim.b[buf].archive_context_source
    if not next_buf then return buf end
    buf = next_buf
  end
end

local function is_article(buf)
  if not valid(buf) then return false end
  if states[buf] or vim.b[buf].texttools_workflow_id or vim.b[buf].agenda_page_flow then return true end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, math.min(80, vim.api.nvim_buf_line_count(buf)), false)) do
    if line:match '^=== ARTIKEL ===%s*$' then return true end
  end
  return false
end

function M.current_source()
  local buf = M.source(vim.api.nvim_get_current_buf())
  return buf and is_article(buf) and buf or nil
end

local function state_for(buf)
  if not states[buf] then
    states[buf] = {
      entries = { { id = 1, message = 'Artikel geopend.', level = vim.log.levels.INFO, time = os.date '%H:%M' } },
      tasks = {},
      issues = {},
      runs = {},
      serial = 1,
    }
  end
  return states[buf]
end

local function first_line(text) return tostring(text or ''):match '([^\n]+)' or '' end

local function shorten(text, width)
  if vim.fn.strdisplaywidth(text) <= width then return text end
  local result = vim.fn.strcharpart(text, 0, math.max(1, width - 1))
  while vim.fn.strdisplaywidth(result) > width - 1 do
    result = vim.fn.strcharpart(result, 0, vim.fn.strchars(result) - 1)
  end
  return result .. '…'
end

local function label(action) return action:gsub('^AI · ', ''):gsub('^Artikel · ', ''):gsub('^Publicatie · ', '') end

local function ordered_tasks(state)
  local tasks = {}
  for _, task in pairs(state.tasks) do
    tasks[#tasks + 1] = task
  end
  table.sort(tasks, function(a, b) return a.order < b.order end)
  return tasks
end

local function running_lines(state)
  local groups, rows = {}, {}
  for _, task in ipairs(ordered_tasks(state)) do
    local name = label(task.action)
    if not groups[name] then
      groups[name] = { name = name, count = 0 }
      rows[#rows + 1] = groups[name]
    end
    groups[name].count = groups[name].count + 1
  end
  local lines = {}
  for _, group in ipairs(rows) do
    lines[#lines + 1] = group.name .. (group.count > 1 and (' (' .. group.count .. ')') or '')
  end
  return lines
end

local function task_status(state)
  local tasks = ordered_tasks(state)
  if #tasks == 0 then return nil end
  return 'Bezig: ' .. label(tasks[1].action) .. (#tasks > 1 and (' · ' .. #tasks .. ' taken') or '')
end

local function status(state, compact)
  local attention = state.attention
  local running = task_status(state)
  if attention then
    local prefix = attention.level >= vim.log.levels.ERROR and 'Fout' or 'Aandacht'
    if compact then return (attention.level >= vim.log.levels.ERROR and 'Fout opgetreden' or 'Aandacht nodig') .. (running and (' · ' .. running) or '') end
    return prefix .. ': ' .. first_line(attention.message) .. (running and (' | ' .. running) or '')
  end
  return running or state.summary or 'Geen geregistreerde taken'
end

-- Deze samenvatting blijft in de vensterkop staan, buiten de scrollbare tekst.
local function process_header(state, width)
  local names = running_lines(state)
  if #names == 0 then return ' Activiteit · geen geregistreerde taken' end
  local result = ' Bezig: '
  for index, name in ipairs(names) do
    local suffix = index < #names and (' · +' .. (#names - index)) or ''
    local candidate = result .. (index > 1 and ' · ' or '') .. name
    if vim.fn.strdisplaywidth(candidate .. suffix) > width then
      if index > 1 then return result .. ' · +' .. (#names - index + 1) end
      return shorten(result .. (index > 1 and ' · ' or '') .. name, math.max(1, width - #suffix)) .. suffix
    end
    result = candidate
  end
  return result
end

function M.statusline(buf)
  buf = M.source(buf)
  local state = buf and states[buf]
  if not enabled or not state then return '' end
  return shorten(status(state, true), 52):gsub('%%', '%%%%')
end

local function save_preferences()
  if not preference_path then return end
  pcall(function()
    vim.fn.mkdir(vim.fn.fnamemodify(preference_path, ':h'), 'p')
    vim.fn.writefile({ vim.json.encode { version = 2, visible = visible, expanded = expanded } }, preference_path)
  end)
end

local function request_refresh()
  if not enabled or queued then return end
  queued = true
  vim.schedule(function()
    queued = false
    refresh()
  end)
end

local function add_entry(state, message, level, options)
  message = tostring(message or ''):gsub('\r\n', '\n'):gsub('\r', '\n')
  if message == '' then return end
  -- Begrens sessiegeheugen; het technische logboek blijft apart beschikbaar.
  message = vim.fn.strcharpart(message, 0, 8000)
  local last = state.entries[#state.entries]
  if
    last
    and last.message == message
    and last.level == level
    and last.kind == options.kind
    and last.action == options.action
    and last.run_id == options.run_id
  then
    last.time = os.date '%H:%M'
    return last
  end
  state.serial = state.serial + 1
  local entry = {
    id = state.serial,
    message = message,
    level = level,
    time = os.date '%H:%M',
    kind = options.kind,
    detail = options.detail == true and level < vim.log.levels.WARN,
    action = options.action,
    run_id = options.run_id,
  }
  state.entries[#state.entries + 1] = entry
  if #state.entries > limit then
    local removed = table.remove(state.entries, 1)
    if not removed.action then state.issues['unscoped:' .. removed.id] = nil end
  end
  return entry
end

local function update_attention(state)
  state.attention = nil
  for _, issue in pairs(state.issues) do
    if
      not issue.read
      and (not state.attention or issue.level > state.attention.level or (issue.level == state.attention.level and issue.id > state.attention.id))
    then
      state.attention = issue
    end
  end
end

function M.record(buf, message, level, options)
  if not enabled then return false end
  if vim.in_fast_event() then
    vim.schedule(function() M.record(buf, message, level, options) end)
    return true
  end
  buf = M.source(buf)
  if not buf then return false end
  local state = state_for(buf)
  options = options or {}
  level = level or vim.log.levels.INFO
  local entry = add_entry(state, message, level, options)
  if not entry then return true end
  -- Een oud resultaat mag de uitkomst van een nieuwere poging niet wissen.
  local current = not options.run_id or state.runs[options.action] == options.run_id
  entry.historical = not current
  if current and (options.kind == 'success' or options.resolved) and options.action then state.issues[options.action] = nil end
  if current and (level >= vim.log.levels.WARN or options.attention) then
    entry.read = nil
    state.issues[options.action or ('unscoped:' .. entry.id)] = entry
  end
  update_attention(state)
  if current and not entry.detail and options.status then
    state.summary = options.status
  elseif current and not entry.detail and options.kind == 'success' then
    state.summary = first_line(message)
  end
  if current and level >= vim.log.levels.ERROR then state.reveal = true end
  request_refresh()
  return true
end

function M.start(buf, id, action)
  if not enabled then return end
  if vim.in_fast_event() then
    vim.schedule(function() M.start(buf, id, action) end)
    return
  end
  buf = M.source(buf)
  if not buf then return end
  local state = state_for(buf)
  if next(state.tasks) == nil then state.summary = nil end
  state.serial = state.serial + 1
  state.tasks[id] = { action = action, order = state.serial }
  state.runs[action] = id
  request_refresh()
end

function M.finish(buf, id)
  if not enabled then return end
  if vim.in_fast_event() then
    vim.schedule(function() M.finish(buf, id) end)
    return
  end
  buf = M.source(buf)
  local state = buf and states[buf]
  local task = state and state.tasks[id]
  if not task then return end
  state.tasks[id] = nil
  -- Exitcodes bewijzen geen toegepast succes of domeinfout. De publicatie-CLI
  -- gebruikt bijvoorbeeld ook niet-nul bij een vereiste review. Alleen de
  -- bestaande callers melden hun geïnterpreteerde uitkomst.
  request_refresh()
end

local function close_panel(tab)
  local panel = panels[tab]
  panels[tab] = nil
  if panel and vim.api.nvim_win_is_valid(panel.win) then
    local normal_windows = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_win_get_config(win).relative == '' then normal_windows = normal_windows + 1 end
    end
    if normal_windows == 1 then
      -- Als de artikel-split al gesloten is, laat q geen onsluitbaar, laatste
      -- logboekvenster achter. Het verborgen bronbuffer blijft behouden.
      vim.api.nvim_win_set_buf(panel.win, valid(panel.source) and panel.source or vim.api.nvim_create_buf(true, false))
    else
      pcall(vim.api.nvim_win_close, panel.win, true)
    end
  end
end

local function acknowledge(buf)
  local state = states[buf]
  if state then
    for _, issue in pairs(state.issues) do
      issue.read = true
    end
    update_attention(state)
  end
  request_refresh()
end

function M.clear_instruction(buf)
  buf = M.source(buf)
  local state = buf and states[buf]
  if state and state.attention and state.attention.level < vim.log.levels.WARN then
    for action, issue in pairs(state.issues) do
      if issue.level < vim.log.levels.WARN then state.issues[action] = nil end
    end
    update_attention(state)
    request_refresh()
  end
end

local function panel_lines(state)
  if not expanded then
    local entry = state.attention
    if not entry then
      for index = #state.entries, 1, -1 do
        if not state.entries[index].detail and not state.entries[index].historical then
          entry = state.entries[index]
          break
        end
      end
    end
    local prefix = entry
        and (entry.level >= vim.log.levels.ERROR and 'FOUT: ' or (entry.level >= vim.log.levels.WARN and 'LET OP: ' or (entry.kind == 'success' and 'OK: ' or '')))
      or ''
    return { prefix .. first_line(entry and entry.message or 'Nog geen resultaten.') }
  end
  local lines, row_ids = {}, {}
  local entries = {}
  for _, entry in ipairs(state.entries) do
    entries[#entries + 1] = entry
  end
  for index = 1, #entries do
    local entry = entries[index]
    local prefix = entry.level >= vim.log.levels.ERROR and 'FOUT: '
      or (entry.level >= vim.log.levels.WARN and 'LET OP: ' or (entry.kind == 'success' and 'OK: ' or ''))
    if entry.historical then prefix = 'Eerdere poging · ' .. prefix end
    local parts = vim.split(entry.message, '\n', { plain = true })
    lines[#lines + 1] = entry.time .. '  ' .. prefix .. parts[1]
    row_ids[#lines] = entry.id .. ':1'
    for part = 2, #parts do
      lines[#lines + 1] = '       ' .. parts[part]
      row_ids[#lines] = entry.id .. ':' .. part
    end
  end
  if #entries == 0 then lines[1] = 'Nog geen meldingen.' end
  return lines, row_ids
end

local function render(panel)
  if not valid(panel.source) or not vim.api.nvim_win_is_valid(panel.win) then return end
  local state = state_for(panel.source)
  local lines, row_ids = panel_lines(state)
  local width = vim.api.nvim_win_get_width(panel.win)
  if not expanded then lines[1] = shorten(lines[1], width * 2) end
  local old_count = vim.api.nvim_buf_line_count(panel.buf)
  local view = vim.api.nvim_win_call(panel.win, vim.fn.winsaveview)
  local follow = not panel.rendered or not expanded or view.lnum >= old_count
  local anchor = panel.row_ids and panel.row_ids[view.lnum]
  local top = panel.row_ids and panel.row_ids[view.topline]
  local before = vim.api.nvim_buf_get_lines(panel.buf, 0, -1, false)
  if not vim.deep_equal(before, lines) then
    vim.bo[panel.buf].modifiable = true
    vim.api.nvim_buf_set_lines(panel.buf, 0, -1, false, lines)
    vim.bo[panel.buf].modifiable = false
    if follow then
      vim.api.nvim_win_set_cursor(panel.win, { #lines, 0 })
    else
      for index, id in ipairs(row_ids or {}) do
        if id == anchor then view.lnum = index end
        if id == top then view.topline = index end
      end
      view.lnum = math.min(view.lnum, #lines)
      vim.api.nvim_win_call(panel.win, function() vim.fn.winrestview(view) end)
    end
  end
  panel.row_ids = row_ids
  local height = expanded and math.max(2, math.min(12, math.floor(vim.o.lines / 3))) or 2
  if vim.api.nvim_win_get_height(panel.win) ~= height then pcall(vim.api.nvim_win_set_height, panel.win, height) end
  vim.wo[panel.win].wrap = true
  vim.wo[panel.win].linebreak = expanded
  vim.wo[panel.win].breakindent = false
  vim.wo[panel.win].showbreak = ''
  vim.wo[panel.win].winbar = process_header(state, width):gsub('%%', '%%%%')
  vim.wo[panel.win].statusline = ' e:' .. (expanded and 'compact' or 'logboek') .. '  l:technisch  q:sluiten'
  vim.api.nvim_buf_clear_namespace(panel.buf, M.namespace, 0, -1)
  for index, line in ipairs(lines) do
    local content = line:gsub('^%d%d:%d%d  ', '')
    local group = content:match '^FOUT:' and 'ErrorMsg' or (content:match '^LET OP:' and 'WarningMsg' or (content:match '^OK:' and 'DiagnosticOk' or nil))
    if group then vim.api.nvim_buf_add_highlight(panel.buf, M.namespace, group, index - 1, 0, -1) end
  end
  panel.rendered = true
end

local function create_panel(tab, source, source_win)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'texttools_activity'
  vim.b[buf].texttools_activity_source = source
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, { split = 'below', win = source_win, height = 2 })
  if not ok then
    vim.api.nvim_buf_delete(buf, { force = true })
    return
  end
  local panel = { win = win, buf = buf, source = source }
  panels[tab] = panel
  vim.wo[win].number, vim.wo[win].relativenumber = false, false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].foldenable = false
  vim.wo[win].colorcolumn = ''
  vim.wo[win].winfixheight = true
  vim.wo[win].winblend = 0
  vim.wo[win].winhighlight = 'Normal:Normal,NormalNC:Normal,EndOfBuffer:Normal'
  local opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set('n', 'q', function() M.toggle() end, vim.tbl_extend('force', opts, { desc = 'Activiteit sluiten (ook tijdens werk)' }))
  vim.keymap.set('n', 'e', function() M.expand() end, vim.tbl_extend('force', opts, { desc = 'Artikel-logboek uitklappen' }))
  vim.keymap.set('n', 'a', function() acknowledge(panel.source) end, vim.tbl_extend('force', opts, { desc = 'Melding als gelezen markeren' }))
  vim.keymap.set(
    'n',
    'l',
    function() require('workflow_log').show { buf = panel.source } end,
    vim.tbl_extend('force', opts, { desc = 'Technische tijdlijn van dit artikel openen' })
  )
  return panel
end

refresh = function()
  if drawing or not enabled then return end
  drawing = true
  local tab = vim.api.nvim_get_current_tabpage()
  local win = vim.api.nvim_get_current_win()
  local current = vim.api.nvim_get_current_buf()
  -- Een dialoog mag niet door layoutwijzigingen verspringen.
  if vim.api.nvim_win_get_config(win).relative == '' then
    local source = M.source(current)
    local panel = panels[tab]
    local state = source and states[source]
    if source and is_article(source) and (visible or (state and state.reveal)) then
      if panel and not vim.api.nvim_win_is_valid(panel.win) then
        panels[tab] = nil
        panel = nil
      end
      if not panel then panel = create_panel(tab, source, win) end
      if panel and panel.source ~= source then
        panel.source, panel.rendered = source, false
        vim.b[panel.buf].texttools_activity_source = source
      end
    elseif panel then
      close_panel(tab)
    end
  end
  for panel_tab, panel in pairs(panels) do
    if not vim.api.nvim_tabpage_is_valid(panel_tab) or not valid(panel.source) then
      close_panel(panel_tab)
    else
      render(panel)
    end
  end
  drawing = false
  vim.cmd 'redrawstatus'
end

function M.toggle()
  local panel = panels[vim.api.nvim_get_current_tabpage()]
  if panel and vim.api.nvim_win_is_valid(panel.win) then
    visible = false
  else
    visible = not visible
  end
  if not visible then
    for _, state in pairs(states) do
      state.reveal = nil
    end
    for tab in pairs(panels) do
      close_panel(tab)
    end
  end
  save_preferences()
  request_refresh()
end

function M.expand()
  visible, expanded = true, not expanded
  for _, panel in pairs(panels) do
    panel.rendered = false
  end
  save_preferences()
  request_refresh()
end

function M.snapshot(buf)
  buf = M.source(buf)
  return buf and vim.deepcopy(states[buf]) or nil
end

function M.panel_visible(buf)
  local panel = panels[vim.api.nvim_get_current_tabpage()]
  return panel and vim.api.nvim_win_is_valid(panel.win) and panel.source == M.source(buf) or false
end

function M.setup(options)
  options = options or {}
  enabled = true
  M.namespace = vim.api.nvim_create_namespace 'texttools_activity'
  preference_path = options.preferences or (vim.fn.stdpath 'state' .. '/texttools/activity.json')
  if vim.fn.filereadable(preference_path) == 1 then
    local ok, preferences = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(preference_path), '\n')) end)
    if ok and type(preferences) == 'table' then
      visible = preferences.visible ~= false
      expanded = preferences.version == 2 and preferences.expanded == true
    end
  end
  local group = vim.api.nvim_create_augroup('texttools_activity', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'TabEnter', 'VimResized' }, { group = group, callback = request_refresh })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(event)
      for tab, panel in pairs(panels) do
        if tostring(panel.win) == event.match then
          panels[tab] = nil
          -- :tabclose sluit ook zijn logboekvenster. Dat is geen verzoek om
          -- de zichtbaarheid in alle overige tabs te veranderen.
          vim.schedule(function()
            if vim.api.nvim_tabpage_is_valid(tab) then
              visible = false
              for _, state in pairs(states) do
                state.reveal = nil
              end
              save_preferences()
            end
            request_refresh()
          end)
        end
      end
      request_refresh()
    end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(event)
      states[event.buf] = nil
      request_refresh()
    end,
  })
  vim.api.nvim_create_user_command('TexttoolsActiviteit', function(command)
    if command.bang then
      M.expand()
    else
      M.toggle()
    end
  end, { bang = true, force = true, desc = 'Artikel-logboek tonen/verbergen (! = compact/uitgebreid)' })
  vim.keymap.set('n', '<leader>kl', M.toggle, { desc = 'Artikel-logboek tonen/verbergen' })
  request_refresh()
end

return M
