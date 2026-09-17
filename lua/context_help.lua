-- Herbruikbare, bufferafhankelijke hulp voor Texttools-werkschermen.

local M = { _entries = {} }

local function help_lines(entry)
  local lines = { entry.title or 'Hulp', '' }
  vim.list_extend(lines, entry.lines or {})
  table.insert(lines, '')
  table.insert(lines, 'Sluiten: q of Escape')
  return lines
end

function M.show(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local entry = M._entries[buf]
  if not entry then
    vim.notify(
      'Voor dit scherm is geen contextuele hulp geregistreerd. Gebruik <leader>ah voor de algemene artikelhulp.',
      vim.log.levels.INFO
    )
    return nil
  end

  local lines = help_lines(entry)
  local width = 48
  for _, line in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(line) + 2)
  end
  width = math.min(width, math.max(20, vim.o.columns - 6))
  local height = math.min(#lines, math.max(6, vim.o.lines - 6))
  local help_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, lines)
  vim.bo[help_buf].modifiable = false
  vim.bo[help_buf].bufhidden = 'wipe'
  vim.bo[help_buf].filetype = 'text'
  local win = vim.api.nvim_open_win(help_buf, true, {
    relative = 'editor',
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = 'minimal',
    border = 'rounded',
    title = ' Contextuele hulp ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  local close = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close, { buffer = help_buf, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = help_buf, nowait = true })
  return help_buf, win
end

function M.register(buf, entry)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  M._entries[buf] = entry
  vim.keymap.set('n', '<leader>kh', function() M.show(buf) end, {
    buffer = buf,
    desc = '[K]rant contextuele [h]ulp',
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function() M._entries[buf] = nil end,
  })
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.keymap.set('n', '<leader>kh', function() M.show() end, {
    desc = '[K]rant contextuele [h]ulp',
  })
  vim.api.nvim_create_user_command('ContextHelp', function() M.show() end, {
    desc = 'Toon hulp voor het huidige Texttools-scherm',
  })
end

return M
