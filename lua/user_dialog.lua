-- Required questions and text input use a native floating presentation.
-- Manually opened choice lists may use an injected fuzzy-picker provider.
local M = {}
local notifications = require('texttools_notify')
local queue, active = {}, false
local active_request, active_win
local postponed, question_serial = {}, 0
local suspend_active
local manual_select_provider
local function focus_question(buf)
  if not active_request or active_request.source_buf ~= buf
      or not active_win or not vim.api.nvim_win_is_valid(active_win) then
    return false
  end
  local tab = vim.api.nvim_win_get_tabpage(active_win)
  if vim.api.nvim_tabpage_is_valid(tab) then vim.api.nvim_set_current_tabpage(tab) end
  vim.api.nvim_set_current_win(active_win)
  return true
end
local function has_question(buf)
  if active_request and active_request.source_buf == buf then return true end
  for _, requests in ipairs({ queue, postponed }) do
    for _, request in ipairs(requests) do if request.source_buf == buf then return true end end
  end
  return false
end
-- Alleen een leesvenster op de bestaande queue; geen tweede vraagregistratie.
M.has_question = has_question
-- Bestaande stappen mogen hun besliscode behouden, maar wachten nooit op de
-- editorhoofdthread. Alleen expliciet geregistreerde UI-acties/callbacks
-- draaien in deze coroutine; domeinstate blijft in de bestaande workflows.
local waiting = {}
local workflows = setmetatable({}, { __mode = 'k' })
local function pack(...) return { n = select('#', ...), ... } end
local function interactive() return #vim.api.nvim_list_uis() > 0 end
local function resume_workflow(thread, ...)
  local result = pack(coroutine.resume(thread, ...))
  if not result[1] then error(result[2], 0) end
  if coroutine.status(thread) == 'suspended' then
    assert(result[2] == waiting, 'Onverwachte yield buiten een UI-keuze')
    return
  end
  workflows[thread] = nil
  return unpack(result, 2, result.n)
end

function M.run(callback, ...)
  local thread = coroutine.running()
  if not interactive() or (thread and workflows[thread]) then return callback(...) end
  thread = coroutine.create(callback)
  workflows[thread] = true
  return resume_workflow(thread, ...)
end

function M.action(callback)
  local active_actions = {}
  return function(...)
    local buf = notifications.source_buffer()
    if active_actions[buf] or has_question(buf) then
      if not focus_question(buf) then
        notifications.workflow('Deze handeling wacht al op een keuze. Beantwoord die vraag of hervat met :TexttoolsVraag.',
          vim.log.levels.INFO, { buf = buf })
      end
      return
    end
    active_actions[buf] = true
    return M.run(function(...)
      local result = pack(pcall(callback, ...))
      active_actions[buf] = nil
      if not result[1] then error(result[2], 0) end
      return unpack(result, 2, result.n)
    end, ...)
  end
end

-- Expliciete registratie-adapters, geen globale wijziging van Neovim-API's.
function M.keymap(mode, lhs, rhs, opts)
  vim.keymap.set(mode, lhs, type(rhs) == 'function' and M.action(rhs) or rhs, opts)
end
function M.command(name, callback, opts)
  vim.api.nvim_create_user_command(name, M.action(callback), opts)
end

local function source_buffer(opts)
  local buf = opts.source_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  return vim.b[buf].user_dialog_source or vim.b[buf].pubble_photo_source
    or vim.b[buf].edition_source_buf or buf
end

local function next_dialog()
  if active or #queue == 0 then return end
  active = true
  local request = table.remove(queue, 1)
  active_request = request
  local opts, items = request.opts, request.items
  if request.provider then
    local finished = false
    local ok = pcall(request.provider, items, opts, function(item, index)
      if finished then return end
      finished = true
      active, active_request, active_win = false, nil, nil
      vim.schedule(next_dialog)
      request.done(item, index)
    end)
    if ok then return end
    -- A missing/broken optional picker must never make a menu unusable.
    -- Continue below with the native overlay for this request.
  end
  vim.cmd('stopinsert')
  local return_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.b[buf].user_dialog_source = request.source_buf
  local vim_edit = opts.input and opts.vim_edit == true
  local width = math.max(1, math.min(90, vim.o.columns - 4))
  local lines = vim.split(opts.prompt or 'Maak een keuze', '\n', { plain = true })
  table.insert(lines, '')
  local first = #lines + 1
  if opts.input then table.insert(lines, opts.default or '')
  else
    for i, item in ipairs(items) do
      table.insert(lines, string.format('%d. %s', i, opts.format_item and opts.format_item(item) or tostring(item)))
    end
  end
  table.insert(lines, '')
  table.insert(lines, opts.input
    and (opts.required and 'Esc: Normal • Enter: antwoorden • Ctrl-C: uitstellen • :TexttoolsVraag: hervatten'
      or 'Esc: Normal • Enter: antwoorden • Ctrl-C: annuleren')
    or (opts.required and 'Enter: antwoorden • Esc/q: uitstellen • :TexttoolsVraag: hervatten' or 'Enter: kiezen • Escape: annuleren'))
  if vim_edit then
    -- Keep help outside the editable text: normal Vim motions, paste and undo
    -- must never turn prompt/footer lines into the submitted value.
    lines = vim.split(opts.default or '', '\n', { plain = true })
    first = 1
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = opts.input == true
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  local visual_lines = 0
  for _, line in ipairs(lines) do
    visual_lines = visual_lines + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  local height = math.max(1, math.min(visual_lines, vim.o.lines - 6))
  local description_buf, description_win
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  if vim_edit and type(opts.description) == 'string' and opts.description ~= '' then
    local context = vim.split(opts.description, '\n', { plain = true })
    local context_rows = 0
    for _, line in ipairs(context) do context_rows = context_rows + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width)) end
    local context_height = math.max(1, math.min(context_rows, vim.o.lines - height - 8))
    local context_row = math.max(0, math.floor((vim.o.lines - height - context_height - 3) / 2))
    row = context_row + context_height + 2
    description_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(description_buf, 0, -1, false, context)
    vim.bo[description_buf].modifiable = false
    vim.bo[description_buf].buftype = 'nofile'
    vim.bo[description_buf].swapfile = false
    description_win = vim.api.nvim_open_win(description_buf, false, {
      relative = 'editor', width = width, height = context_height,
      row = context_row, col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = 'minimal', border = 'rounded', title = ' Ter controle ', focusable = true,
    })
    vim.wo[description_win].wrap = true
    vim.wo[description_win].winblend = 0
    vim.wo[description_win].winhighlight = 'Normal:Normal,FloatBorder:FloatBorder'
  end
  local function close_description()
    if description_win and vim.api.nvim_win_is_valid(description_win) then vim.api.nvim_win_close(description_win, true) end
    if description_buf and vim.api.nvim_buf_is_valid(description_buf) then vim.api.nvim_buf_delete(description_buf, { force = true }) end
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = row,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal', border = 'rounded',
    title = vim_edit and (' ' .. (opts.prompt or 'Invoer'):gsub('%c', ' ') .. ' ')
      or (opts.required and ' Antwoord nodig ' or ' Keuze '),
    footer = vim_edit and (opts.footer or ' Esc: Normal | Enter: zoeken | Ctrl-C: annuleren ') or nil,
  })
  active_win = win
  vim.wo[win].wrap = true
  vim.wo[win].winblend = 0
  vim.wo[win].winhighlight = 'Normal:Normal,FloatBorder:FloatBorder'
  vim.wo[win].cursorline = true
  local selected = opts.input and 1 or math.max(1, math.min(opts.default or 1, #items))
  local finished = false
  local function input_value()
    if vim_edit then return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
    return vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1]
  end
  local function cursor()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_cursor(win, { first + selected - 1, 0 }) end
  end
  local function finish(index)
    if finished then return end
    finished = true
    local restore_focus = vim.api.nvim_get_current_win() == win
    if opts.input then vim.cmd('stopinsert') end
    close_description()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    if restore_focus and vim.api.nvim_win_is_valid(return_win) then vim.api.nvim_set_current_win(return_win) end
    active, active_request, active_win = false, nil, nil
    suspend_active = nil
    vim.schedule(next_dialog)
    if request.question_id then
      notifications.workflow('Vraag beantwoord.', nil, {
        buf = request.source_buf, action = 'Vraag · ' .. request.question_id,
        resolved = true, detail = true,
      })
    end
    request.done(opts.input and index or (index and items[index] or nil), opts.input and nil or index)
  end
  suspend_active = function(postpone)
    local restore_focus = vim.api.nvim_get_current_win() == win
    if opts.input then
      request.opts.default = input_value()
    else request.opts.default = selected end
    finished = true
    close_description()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    active, active_request, active_win = false, nil, nil
    suspend_active = nil
    if postpone then
      if not request.question_id then
        question_serial = question_serial + 1
        request.question_id = question_serial
      end
      postponed[#postponed + 1] = request
      notifications.workflow('Vraag uitgesteld: ' .. (opts.prompt or 'Maak een keuze')
        .. '\nDe bijbehorende handeling wacht op je antwoord. Hervat met :TexttoolsVraag.', nil, {
          buf = request.source_buf, attention = true, kind = 'question', action = 'Vraag · ' .. request.question_id,
        })
      if restore_focus and vim.api.nvim_win_is_valid(return_win) then vim.api.nvim_set_current_win(return_win) end
      vim.schedule(next_dialog)
    else
      table.insert(queue, 1, request)
    end
  end
  local function map(key, action) vim.keymap.set('n', key, action, { buffer = buf, nowait = true, silent = true }) end
  local function accept()
    if opts.input then
      finish(input_value())
    else
      local index = vim.api.nvim_win_get_cursor(win)[1] - first + 1
      finish(index >= 1 and index <= #items and index or selected)
    end
  end
  map('<CR>', accept)
  if opts.input then
    vim.keymap.set('i', '<CR>', function() vim.cmd('stopinsert'); accept() end, { buffer = buf })
    vim.keymap.set('i', '<Esc>', function()
      vim.cmd('stopinsert')
    end, { buffer = buf })
    -- Escape is uitsluitend een moduswissel, ook bij herhaald drukken in
    -- Normal. Alleen expliciet annuleren/uitstellen mag een vervolg aanroepen.
    map('<Esc>', '<Nop>')
    vim.keymap.set('i', '<C-c>', function()
      vim.cmd('stopinsert')
      if opts.required then suspend_active(true) else finish(nil) end
    end, { buffer = buf })
  end
  for _, key in ipairs({ '<Esc>', '<C-c>' }) do
    if not (opts.input and key == '<Esc>') then
      map(key, function() if opts.required then suspend_active(true) else finish(nil) end end)
    end
  end
  if not opts.input then
    if opts.required then map('q', function() suspend_active(true) end) end
    for _, key in ipairs({ 'j', '<Down>' }) do map(key, function() selected = math.min(#items, selected + 1); cursor() end) end
    for _, key in ipairs({ 'k', '<Up>' }) do map(key, function() selected = math.max(1, selected - 1); cursor() end) end
    for i = 1, math.min(9, #items) do map(tostring(i), function() finish(i) end) end
    for shortcut, index in pairs(opts.shortcuts or {}) do
      if type(index) == 'number' and index >= 1 and index <= #items then
        map(shortcut, function() finish(index) end)
      end
    end
  end
  vim.api.nvim_create_autocmd('WinClosed', { pattern = tostring(win), once = true, callback = function()
    if finished then return end
    -- Sluiten stelt een verplichte vraag uit; het is nooit een antwoord.
    if opts.required then
      suspend_active(true)
    else finish(nil) end
  end })
  cursor()
  if opts.on_open then opts.on_open(buf, win) end
  if opts.input then vim.cmd('startinsert!') end
end

-- Breng een zichtbare vraag voor deze bronbuffer terug naar voren. Een vraag
-- van een ander artikel wordt nooit overgenomen.
M.focus = focus_question

function M.select(items, opts, done)
  if #items == 0 then done(nil); return end
  opts = opts or {}
  table.insert(queue, {
    items = items,
    opts = opts,
    done = notifications.bind(opts.source_buf, done),
    source_buf = source_buffer(opts),
    provider = not opts.required and not opts.native and manual_select_provider or nil,
  })
  vim.schedule(next_dialog)
end

function M.confirm(prompt, buttons, default, required)
  if interactive() then
    local thread = coroutine.running()
    assert(thread and workflows[thread], 'Interactieve bevestiging moet via user_dialog.run/action lopen')
    local buf = notifications.source_buffer()
    local revision = buf and vim.api.nvim_buf_is_valid(buf) and require('buffer_revision').capture(buf)
    local answered, answer, suspended = false, nil, false
    M.confirm_async(prompt, buttons, default, required, function(choice)
      if revision and not require('buffer_revision').matches(buf, revision) then
        notifications.workflow('Artikel gewijzigd of gesloten tijdens de keuze. Er is geen besluit toegepast; start de handeling opnieuw.',
          vim.log.levels.WARN, { buf = buf })
        choice = 0
      end
      answered, answer = true, choice
      if suspended then resume_workflow(thread, choice) end
    end, { source_buf = buf })
    if answered then return answer end
    suspended = true
    return coroutine.yield(waiting)
  end
  -- Alleen een headless client heeft geen overlay. Tests behouden hun
  -- injecteerbare native antwoord, zonder verborgen wachtlus voor een UI.
  local choice = vim.fn.confirm(prompt, buttons, default or 1)
  while required and choice == 0 do
    choice = vim.fn.confirm(prompt, buttons, default or 1)
  end
  return choice
end

function M.inputlist(menu)
  if #vim.api.nvim_list_uis() == 0 then return vim.fn.inputlist(menu) end
  local labels = vim.list_slice(menu, 2)
  for index, label in ipairs(labels) do labels[index] = label:gsub('^%s*%d+[.)]%s*', '') end
  return M.confirm(menu[1], table.concat(labels, '\n'), 1, true)
end

function M.setup(opts)
  opts = opts or {}
  manual_select_provider = opts.manual_select
  if manual_select_provider == M.select then manual_select_provider = nil end
  vim.ui.select = M.select
  vim.ui.input = M.input
  vim.api.nvim_create_user_command('TexttoolsVraag', M.resume, { force = true, desc = 'Uitgestelde vraag hervatten' })
end

-- Alleen de bestaande callbacks/invoerdrafts worden bewaard. Hervatten kiest
-- nooit impliciet een antwoord en kan een verdwenen bron niet vervangen.
function M.resume()
  while #postponed > 0 do
    local request = table.remove(postponed, 1)
    if not request.source_buf or vim.api.nvim_buf_is_valid(request.source_buf) then
      table.insert(queue, 1, request)
      vim.schedule(next_dialog)
      return true
    end
  end
  notifications.workflow('Geen uitgestelde vragen.')
  return false
end

-- Nieuwe callers met een vervolgcallback gebruiken dezelfde asynchrone
-- keuzelaag. Oude synchrone confirm-callers behouden hun veilige native pad.
function M.confirm_async(prompt, buttons, default, required, done, options)
  -- CLI/headless-tests hebben geen invoeroppervlak. Behoud daar de bestaande
  -- injecteerbare native bevestiging; interactieve clients wachten via select.
  if #vim.api.nvim_list_uis() == 0 then
    done(M.confirm(prompt, buttons, default, required))
    return
  end
  local items = vim.split(buttons, '\n', { plain = true })
  for index, item in ipairs(items) do items[index] = item:gsub('&', '') end
  options = vim.tbl_extend('force', options or {}, {
    prompt = prompt, default = default or 1, required = required == true, native = true,
  })
  M.select(items, options, function(_, index) done(index or 0) end)
end

function M.input(opts, done)
  opts = vim.tbl_extend('force', opts or {}, { input = true })
  local request = { items = {}, opts = opts, done = notifications.bind(opts.source_buf, done), source_buf = source_buffer(opts) }
  if opts.priority then
    -- Explicit manual work may pause an overlay, never answer or discard it.
    -- An optional external picker without a suspension hook finishes normally.
    if active and suspend_active then suspend_active() end
    table.insert(queue, 1, request)
  else
    table.insert(queue, request)
  end
  vim.schedule(next_dialog)
end

return M
