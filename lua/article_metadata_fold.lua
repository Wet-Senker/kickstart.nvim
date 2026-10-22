-- Alleen presentatie: YAML blijft letterlijk in de buffer/het bestand staan.
-- Eén handmatige vouw voorkomt een foldexpr over alle artikelregels en laat
-- eventuele eigen vouwen elders in het document intact.
local M = {}
local buffers, windows = {}, {}
local foldtext = "v:lua.require'article_metadata_fold'.text()"

local function eligible(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
    and (vim.bo[buf].filetype == 'markdown' or vim.bo[buf].filetype == 'text')
end

-- Lees alleen het voorblok, niet de artikelbody. Een gewone Markdown-
-- scheidingslijn of codevoorbeeld zonder artikelgrens is geen metadatafold.
local function metadata_end(buf)
  local count = vim.api.nvim_buf_line_count(buf)
  local chunk, offset = {}, -1
  local function line(at)
    if at >= count then return nil end
    if at < offset or at >= offset + #chunk then
      offset = at
      chunk = vim.api.nvim_buf_get_lines(buf, at, math.min(at + 32, count), false)
    end
    return chunk[at - offset + 1]
  end
  if line(0) ~= '---' then return nil end
  local ending, has_key
  for at = 1, count - 1 do
    local value = line(at)
    if not ending then
      if value:match('^=== ARTIKEL ===%s*$') or value:match('^=== AGENDAPAGINA ===%s*$') then
        return nil -- Onvolledig voorblok nooit inclusief het artikel verbergen.
      elseif value == '---' then
        ending = at + 1
        if not has_key then return nil end
      elseif value:match('^[%a_][%w_%-]*%s*:') then has_key = true end
    elseif value:match('^=== ARTIKEL ===%s*$') or value:match('^=== AGENDAPAGINA ===%s*$') then
      return ending
    elseif value ~= '' and not value:match('^%s') and not value:match('^[^:]+:') then
      return nil
    end
  end
end

function M.text()
  local state = windows[vim.api.nvim_get_current_win()]
  if state and state.buf == vim.api.nvim_get_current_buf()
      and vim.v.foldstart == 1 and vim.v.foldend == state.ending then
    return 'Technische gegevens · zo openen / zc sluiten'
  end
  -- Een al bestaande custom foldtext voor andere vouwen blijft geldig.
  return state and state.previous_text ~= foldtext and vim.api.nvim_eval(state.previous_text) or vim.fn.foldtext()
end

function M.refresh(buf)
  if not eligible(buf) then return end
  local ending = metadata_end(buf)
  buffers[buf].ending = ending
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      local inherited = windows[win]
      local previous = inherited
      if previous and previous.buf ~= buf then previous = nil end
      -- Niet over een bewust gekozen andere vouwmethode heen schrijven.
      if vim.wo.foldmethod ~= 'manual' then return end
      local level = vim.fn.foldlevel(1)
      -- Een split of terugkeer naar deze buffer kan onze bestaande vouw
      -- overnemen. Herbind dan de presentatie, niet een willekeurige userfold.
      if not previous and level == 1 and vim.wo.foldtext == foldtext
          and buffers[buf].previous_text then
        previous = { buf = buf, ending = ending, previous_text = buffers[buf].previous_text }
        windows[win] = previous
      end
      if level > 1 or (level > 0 and not previous) then return end
      if not ending and not previous then return end
      local view = vim.fn.winsaveview()
      local opened = previous and level > 0 and vim.fn.foldclosed(1) == -1
      if previous and level > 0 then
        vim.cmd('silent! 1foldclose')
        if ending == previous.ending and vim.fn.foldclosedend(1) == ending then
          if opened then vim.cmd('silent! 1foldopen') end
          vim.fn.winrestview(view)
          return
        end
        -- Alleen onze eigen voorblokvouw verwijderen, nooit zE voor de buffer.
        vim.cmd('silent! 1normal! zd')
      end
      if ending then
        local previous_text = vim.wo.foldtext == foldtext and inherited and inherited.previous_text or vim.wo.foldtext
        windows[win] = { buf = buf, ending = ending,
          previous_text = previous and previous.previous_text or previous_text }
        buffers[buf].previous_text = windows[win].previous_text
        vim.wo.foldtext = foldtext
        vim.wo.foldenable = true
        vim.cmd(('silent! 1,%dfold'):format(ending))
        if opened then vim.cmd('silent! 1foldopen') end
      elseif previous then
        if vim.wo.foldtext == foldtext then vim.wo.foldtext = previous.previous_text end
        windows[win] = nil
      end
      vim.fn.winrestview(view)
    end)
  end
end

local function schedule(buf)
  local state = buffers[buf]
  if not state or state.pending then return end
  state.pending = true
  vim.schedule(function()
    if not buffers[buf] then return end
    state.pending = false
    M.refresh(buf)
  end)
end

function M.attach(buf)
  if not eligible(buf) then return end
  if not buffers[buf] then
    buffers[buf] = {}
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first)
        local state = buffers[buf]
        -- Reguliere tekstbewerking onder het voorblok vraagt geen herscan.
        if state and state.ending and first >= state.ending then return end
        schedule(buf)
      end,
      on_reload = function() schedule(buf) end,
      on_detach = function() buffers[buf] = nil end,
    })
  end
  schedule(buf)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('ArticleMetadataFold', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'WinEnter' }, {
    group = group,
    callback = function(event) M.attach(event.buf) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(event) windows[tonumber(event.match)] = nil end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do M.attach(buf) end
end

return M
