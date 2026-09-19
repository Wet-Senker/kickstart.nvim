-- Required questions and text input use a native floating presentation.
-- Manually opened choice lists may use an injected fuzzy-picker provider.
local M = {}
local queue, active = {}, false
local suspend_active
local manual_select_provider

local function next_dialog()
  if active or #queue == 0 then return end
  active = true
  local request = table.remove(queue, 1)
  local opts, items = request.opts, request.items
  if request.provider then
    local finished = false
    local ok = pcall(request.provider, items, opts, function(item, index)
      if finished then return end
      finished = true
      active = false
      vim.schedule(next_dialog)
      request.done(item, index)
    end)
    if ok then return end
    -- A missing/broken optional picker must never make a menu unusable.
    -- Continue below with the native overlay for this request.
  end
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
  opts = opts or {}
  table.insert(queue, {
    items = items,
    opts = opts,
    done = done,
    provider = not opts.required and manual_select_provider or nil,
  })
  vim.schedule(next_dialog)
end

-- Ja/nee-vragen gaan altijd via Neovims ingebouwde prompt (`vim.fn.confirm`).
-- Die maakt geen zwevend venster aan en houdt de hoofd-thread niet in een
-- `vim.wait`-lus, dus hij kan nooit vastlopen in het kwetsbare verse-import-
-- venster waar het overlay-scherm op sommige Neovim-versies de eventloop
-- wedgede. De interactieve lijst-menu's (select/input) houden wél hun overlay;
-- die roept de redacteur zelf op, buiten dat kwetsbare moment.
-- Handmatige keuzelijsten mogen hierboven via de fuzzy provider lopen; invoer
-- en verplichte selecties behouden hun overlay. `required` betekent hier: een
-- reflexmatige Escape mag de vraag niet beantwoorden. `vim.fn.confirm` geeft 0
-- bij Escape; voor een verplichte vraag stellen we hem dan opnieuw, net als het
-- oude overlay-gedrag.
function M.confirm(prompt, buttons, default, required)
  local choice = vim.fn.confirm(prompt, buttons, default or 1)
  while required and choice == 0 do
    choice = vim.fn.confirm(prompt, buttons, default or 1)
  end
  return choice
end

function M.inputlist(menu)
  if #vim.api.nvim_list_uis() == 0 then return vim.fn.inputlist(menu) end
  return M.confirm(menu[1], table.concat(vim.list_slice(menu, 2), '\n'), 1, true)
end

function M.setup(opts)
  opts = opts or {}
  manual_select_provider = opts.manual_select
  if manual_select_provider == M.select then manual_select_provider = nil end
  vim.ui.select = M.select
  vim.ui.input = M.input
end

function M.input(opts, done)
  opts = vim.tbl_extend('force', opts or {}, { input = true })
  table.insert(queue, { items = {}, opts = opts, done = done })
  vim.schedule(next_dialog)
end

return M
