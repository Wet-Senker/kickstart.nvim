-- Alleen vensternavigatie: nooit documentinhoud, domeinstate of opslag wijzigen.
local M = {}
local history = {}
local options = { 'wrap', 'linebreak', 'breakindent', 'breakindentopt', 'showbreak',
  'smoothscroll', 'list', 'colorcolumn', 'spell', 'conceallevel', 'concealcursor',
  'number', 'relativenumber', 'signcolumn', 'foldenable', 'foldmethod', 'foldlevel', 'winbar', 'statusline',
  'winhighlight', 'winfixheight', 'winblend' }

local function switch(win, buf)
  local previous = vim.api.nvim_win_get_buf(win)
  local hidden = vim.bo[previous].bufhidden
  vim.bo[previous].bufhidden = 'hide'
  local ok, err = pcall(vim.api.nvim_win_set_buf, win, buf)
  if vim.api.nvim_buf_is_valid(previous) then vim.bo[previous].bufhidden = hidden end
  if not ok then error(err, 0) end
end

function M.show(buf, settings)
  settings = settings or {}
  local win = settings.win or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then return nil end
  local source = vim.api.nvim_win_get_buf(win)
  if source == buf then return win end
  local saved = { buf = source, view = vim.api.nvim_win_call(win, vim.fn.winsaveview), options = {} }
  for _, option in ipairs(options) do saved.options[option] = vim.wo[win][option] end
  local stack = history[win] or {}
  -- Een handmatige :buffer/:edit is een nieuwe navigatieroute. Geen oude
  -- terugweg blijven opstapelen of later onverwacht naar dat scherm springen.
  if stack[#stack] and stack[#stack].target ~= source then stack = {} end
  history[win] = stack
  stack[#stack + 1] = { target = buf, previous = saved }
  local ok, err = pcall(switch, win, buf)
  if not ok then
    table.remove(stack)
    if #stack == 0 then history[win] = nil end
    error(err, 0)
  end
  if settings.editable then
    vim.bo[buf].bufhidden, vim.bo[buf].buflisted = 'hide', true
  elseif not vim.bo[buf].modifiable then
    vim.bo[buf].modified = false
    vim.keymap.set('n', 'q', function() M.back(buf) end, { buffer = buf, desc = 'Terug naar het vorige scherm' })
  end
  return win
end

function M.back(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    win = nil
    for candidate, stack in pairs(history) do
      if vim.api.nvim_win_is_valid(candidate) and vim.api.nvim_win_get_buf(candidate) == buf
          and stack[#stack] and stack[#stack].target == buf then win = candidate; break end
    end
  end
  local stack = win and history[win]
  if not stack or not stack[#stack] or stack[#stack].target ~= buf then return false end
  local saved
  repeat
    saved = table.remove(stack).previous
  until vim.api.nvim_buf_is_valid(saved.buf) or #stack == 0
  if not vim.api.nvim_buf_is_valid(saved.buf) then saved.buf = vim.api.nvim_create_buf(true, false) end
  switch(win, saved.buf)
  for option, value in pairs(saved.options) do vim.wo[win][option] = value end
  vim.api.nvim_win_call(win, function() vim.fn.winrestview(saved.view) end)
  if #stack == 0 then history[win] = nil end
  if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].bufhidden == 'wipe' and #vim.fn.win_findbuf(buf) == 0 then
    if vim.bo[buf].modified then
      -- Ook handmatig bewerkte hulpschermen nooit ongemerkt weggooien.
      vim.bo[buf].bufhidden, vim.bo[buf].buflisted = 'hide', true
    else vim.api.nvim_buf_delete(buf, { force = true }) end
  end
  return true
end

function M.setup()
  vim.api.nvim_create_user_command('TexttoolsTerug', function() M.back() end,
    { force = true, desc = 'Terug naar de vorige Texttools-buffer zonder werk te verliezen' })
  local group = vim.api.nvim_create_augroup('TexttoolsBufferNavigation', { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', { group = group,
    callback = function(event) history[tonumber(event.match)] = nil end })
end

return M
