-- One native floating presentation, independent of fuzzy-picker providers.
local M = {}
local queue, active = {}, false
local suspend_active

local function next_dialog()
  if active or #queue == 0 then return end
  active = true
  local request = table.remove(queue, 1)
  local opts, items = request.opts, request.items
  vim.cmd('stopinsert')
  local buf = vim.api.nvim_create_buf(false, true)
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
  table.insert(lines, opts.required and 'Enter: antwoord kiezen • Escape sluit deze vraag niet' or 'Enter: kiezen • Escape: annuleren')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = opts.input == true
  local visual_lines = 0
  for _, line in ipairs(lines) do
    visual_lines = visual_lines + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  local height = math.max(1, math.min(visual_lines, vim.o.lines - 6))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor', width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal', border = 'rounded', title = ' Keuze ',
  })
  vim.wo[win].wrap = true
  vim.wo[win].cursorline = true
  local selected = opts.input and 1 or math.max(1, math.min(opts.default or 1, #items))
  local finished = false
  local function cursor()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_cursor(win, { first + selected - 1, 0 }) end
  end
  local function finish(index)
    if finished then return end
    finished = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    active = false
    suspend_active = nil
    vim.schedule(next_dialog)
    request.done(opts.input and index or (index and items[index] or nil), opts.input and nil or index)
  end
  suspend_active = function()
    if opts.input then
      request.opts.default = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1]
    else request.opts.default = selected end
    finished = true
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    active = false
    suspend_active = nil
    table.insert(queue, 1, request)
  end
  local function map(key, action) vim.keymap.set('n', key, action, { buffer = buf, nowait = true, silent = true }) end
  local function accept()
    if opts.input then
      finish(vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1])
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
      if not opts.required then finish(nil) end
    end, { buffer = buf })
  end
  for _, key in ipairs({ '<Esc>', '<C-c>' }) do
    map(key, function() if not opts.required then finish(nil) end end)
  end
  if not opts.input then
    for _, key in ipairs({ 'j', '<Down>' }) do map(key, function() selected = math.min(#items, selected + 1); cursor() end) end
    for _, key in ipairs({ 'k', '<Up>' }) do map(key, function() selected = math.max(1, selected - 1); cursor() end) end
    for i = 1, math.min(9, #items) do map(tostring(i), function() finish(i) end) end
  end
  vim.api.nvim_create_autocmd('WinClosed', { pattern = tostring(win), once = true, callback = function()
    if finished then return end
    -- An externally closed required question is re-presented, never answered.
    if opts.required then
      finished = true
      active = false
      suspend_active = nil
      table.insert(queue, 1, request)
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
      vim.schedule(next_dialog)
    else finish(nil) end
  end })
  cursor()
  if opts.input then vim.cmd('startinsert!') end
end

function M.select(items, opts, done)
  if #items == 0 then done(nil); return end
  table.insert(queue, { items = items, opts = opts or {}, done = done })
  vim.schedule(next_dialog)
end

-- Compatibility boundary for existing synchronous decision hooks. vim.wait
-- services native UI events; unlike fuzzy pickers it starts no nested process.
function M.confirm(prompt, buttons, default, required)
  if #vim.api.nvim_list_uis() == 0 then return vim.fn.confirm(prompt, buttons, default) end
  local items = vim.split(buttons:gsub('&', ''), '\n', { plain = true })
  for i, label in ipairs(items) do items[i] = label:gsub('^%d+%.%s*', '') end
  local result
  -- A timer may request a synchronous question during an existing question.
  -- Suspend/requeue the old one, rather than nesting waits behind its window.
  if suspend_active then suspend_active() end
  table.insert(queue, 1, { items = items,
    opts = { prompt = prompt, default = default, required = required == true },
    done = function(_, index) result = index or 0 end })
  vim.schedule(next_dialog)
  while result == nil do vim.wait(100, function() return result ~= nil end, 10) end
  return result
end

function M.inputlist(menu)
  if #vim.api.nvim_list_uis() == 0 then return vim.fn.inputlist(menu) end
  return M.confirm(menu[1], table.concat(vim.list_slice(menu, 2), '\n'), 1, true)
end

function M.setup()
  vim.ui.select = M.select
  vim.ui.input = M.input
end

function M.input(opts, done)
  opts = vim.tbl_extend('force', opts or {}, { input = true })
  table.insert(queue, { items = {}, opts = opts, done = done })
  vim.schedule(next_dialog)
end

return M
