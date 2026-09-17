-- Herbruikbare, bufferafhankelijke hulp voor Texttools-werkschermen.
--
-- Een registratie mag een vaste tabel of een providerfunctie zijn. Providers
-- worden pas bij het openen uitgevoerd, zodat dezelfde helpknop altijd de
-- actuele workflowfase beschrijft zonder zelf workflowstatus te bewaren.

local M = { _entries = {}, _cleanup_registered = {}, _fallback = nil }

local function normalize_entry(entry)
  if type(entry) ~= 'table' then return nil end
  local normalized = {
    title = type(entry.title) == 'string' and entry.title or 'Hulp',
    status = type(entry.status) == 'string' and entry.status or nil,
    sections = {},
  }
  if type(entry.sections) == 'table' then
    for _, section in ipairs(entry.sections) do
      if type(section) == 'table' and type(section.lines) == 'table' then
        table.insert(normalized.sections, {
          heading = type(section.heading) == 'string' and section.heading or nil,
          lines = vim.deepcopy(section.lines),
        })
      end
    end
  elseif type(entry.lines) == 'table' then
    table.insert(normalized.sections, { lines = vim.deepcopy(entry.lines) })
  end
  return normalized
end

local function resolve_entry(buf)
  local registered = M._entries[buf]
  if registered == nil then registered = M._fallback end
  if type(registered) == 'function' then
    local ok, result = pcall(registered, buf)
    if not ok then
      vim.notify('Contextuele hulp kon niet worden opgebouwd: ' .. tostring(result), vim.log.levels.ERROR)
      return nil, true
    end
    return normalize_entry(result)
  end
  return normalize_entry(registered)
end

function M.set_fallback(provider)
  M._fallback = type(provider) == 'function' and provider or nil
end

local function help_lines(entry)
  local lines = { entry.title or 'Hulp' }
  if entry.status and vim.trim(entry.status) ~= '' then
    table.insert(lines, '')
    table.insert(lines, 'Status')
    table.insert(lines, '  ' .. entry.status)
  end
  for _, section in ipairs(entry.sections or {}) do
    if #section.lines > 0 then
      table.insert(lines, '')
      if section.heading and vim.trim(section.heading) ~= '' then
        table.insert(lines, section.heading)
      end
      for _, line in ipairs(section.lines) do
        table.insert(lines, section.heading and ('  ' .. tostring(line)) or tostring(line))
      end
    end
  end
  table.insert(lines, '')
  table.insert(lines, 'Sluiten: q of Escape')
  return lines
end

function M.show(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local entry, provider_failed = resolve_entry(buf)
  if not entry then
    if provider_failed then return nil end
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
  vim.wo[win].linebreak = true
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
  if not M._cleanup_registered[buf] then
    M._cleanup_registered[buf] = true
    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = buf,
      once = true,
      callback = function()
        M._entries[buf] = nil
        M._cleanup_registered[buf] = nil
      end,
    })
  end
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

M._normalize_entry = normalize_entry
M._resolve_entry = resolve_entry
M._help_lines = help_lines

return M
