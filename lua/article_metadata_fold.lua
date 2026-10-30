-- YAML blijft letterlijk in de buffer/het bestand staan. De aansluitende
-- compatibiliteitsmarker hoort bij dezelfde verborgen technische weergave.
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
local function metadata_end(buf, after_receipt)
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
  local first = 0
  if after_receipt and (line(0) or ''):match('^%*%*Verstuurd naar Pubble op ') then
    first = 1
    if (line(first) or ''):match('^https?://') then first = first + 1 end
    while line(first) == '' do first = first + 1 end
  end
  if line(first) ~= '---' then return nil end
  local ending, has_key, legacy_marker, technical_gap
  for at = first + 1, count - 1 do
    local value = line(at)
    if not ending then
      if value:match('^=== ARTIKEL ===%s*$') or value:match('^=== AGENDAPAGINA ===%s*$') then
        return nil -- Onvolledig voorblok nooit inclusief het artikel verbergen.
      elseif value == '---' then
        ending = at + 1
        technical_gap = true
        if not has_key then return nil end
      elseif value:match('^[%a_][%w_%-]*%s*:') then has_key = true end
    elseif value:match('^=== ARTIKEL ===%s*$') or value:match('^=== AGENDAPAGINA ===%s*$') then
      return ending, first + 1, legacy_marker
    elseif value == 'doublures: beoordeeld' then
      if technical_gap then ending = at + 1 else legacy_marker = true end
    elseif value ~= '' and not require('article_notices').is_log_boundary(value)
        and not value:match('^%s') and not value:match('^[^:]+:') then
      return nil
    elseif value ~= '' then
      technical_gap = false
    end
  end
end

-- Alleen een alleen-lezen momentopname, nooit een tweede bewerkbare bron.
function M.show(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if not eligible(buf) then return end
  local ending, first = metadata_end(buf, true)
  if not ending then
    require('texttools_notify').notify('Dit artikel heeft geen technische gegevens.', vim.log.levels.INFO, { buf = buf })
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, first - 1, ending, false)
  local view = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(view, 0, -1, false, lines)
  vim.bo[view].filetype = 'yaml'
  vim.bo[view].bufhidden = 'wipe'
  vim.bo[view].swapfile = false
  vim.bo[view].readonly = true
  vim.bo[view].modifiable = false
  vim.b[view].texttools_activity_source = buf
  local width = math.min(100, math.max(20, vim.o.columns - 6))
  local height = math.min(#lines, math.max(1, vim.o.lines - 8))
  local win = vim.api.nvim_open_win(view, true, {
    relative = 'editor', style = 'minimal', border = 'rounded',
    width = width, height = height,
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    title = ' Artikelgegevens · alleen lezen ', title_pos = 'center',
    footer = ' Momentopname · q / Escape sluiten ', footer_pos = 'center',
  })
  vim.wo[win].wrap = false
  vim.wo[win].winblend = 0
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close, { buffer = view, nowait = true })
  vim.keymap.set('n', '<Esc>', close, { buffer = view, nowait = true })
  return view, win
end

function M.text()
  local state = windows[vim.api.nvim_get_current_win()]
  if state and state.buf == vim.api.nvim_get_current_buf()
      and vim.v.foldstart == state.first and vim.v.foldend == state.ending then
    return 'Gegevens verborgen · :ArtikelMetadata'
  end
  -- Een al bestaande custom foldtext voor andere vouwen blijft geldig.
  return state and state.previous_text ~= foldtext and vim.api.nvim_eval(state.previous_text) or vim.fn.foldtext()
end

function M.refresh(buf)
  if not eligible(buf) then return end
  local ending, first, legacy_marker = metadata_end(buf, true)
  local state = buffers[buf]
  if legacy_marker and not state.marker_layout_started and vim.bo[buf].modifiable and not vim.bo[buf].readonly then
    state.marker_layout_started = true
    require('duplicate_marker_layout').normalize(buf, function()
      if vim.api.nvim_buf_is_valid(buf) then M.refresh(buf) end
    end)
  end
  buffers[buf].ending = ending
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_call(win, function()
      local inherited = windows[win]
      local previous = inherited
      if previous and previous.buf ~= buf then previous = nil end
      -- Niet over een bewust gekozen andere vouwmethode heen schrijven.
      if vim.wo.foldmethod ~= 'manual' then return end
      local at = first or (previous and previous.first) or 1
      local level = vim.fn.foldlevel(at)
      -- Een split of terugkeer naar deze buffer kan onze bestaande vouw
      -- overnemen. Herbind dan de presentatie, niet een willekeurige userfold.
      if not previous and level == 1 and vim.wo.foldtext == foldtext
          and buffers[buf].previous_text then
        previous = { buf = buf, first = at, ending = ending, previous_text = buffers[buf].previous_text }
        windows[win] = previous
      end
      if level > 1 or (level > 0 and not previous) then return end
      if not ending and not previous then return end
      local view = vim.fn.winsaveview()
      if previous and level > 0 then
        vim.cmd(('silent! %dfoldclose'):format(at))
        if first and vim.fn.foldclosed(at) == first and vim.fn.foldclosedend(at) == ending then
          previous.first, previous.ending = first, ending
          vim.fn.winrestview(view)
          return
        end
        -- Alleen onze eigen voorblokvouw verwijderen, nooit zE voor de buffer.
        vim.cmd(('silent! %dnormal! zd'):format(at))
      end
      if ending then
        local previous_text = vim.wo.foldtext == foldtext and inherited and inherited.previous_text or vim.wo.foldtext
        windows[win] = { buf = buf, first = first, ending = ending,
          previous_text = previous and previous.previous_text or previous_text }
        buffers[buf].previous_text = windows[win].previous_text
        vim.wo.foldtext = foldtext
        vim.wo.foldenable = true
        vim.cmd(('silent! %d,%dfold'):format(first, ending))
      elseif previous then
        if vim.wo.foldtext == foldtext then vim.wo.foldtext = previous.previous_text end
        windows[win] = nil
      end
      vim.fn.winrestview(view)
    end)
  end
end

-- Zoeken, zR of cursorbeweging mogen de machinegegevens niet als werktekst
-- laten verschijnen. Voor inspectie bestaat de expliciete kijkopdracht.
local function keep_closed()
  local win = vim.api.nvim_get_current_win()
  local state = windows[win]
  if not state or state.buf ~= vim.api.nvim_get_current_buf()
      or vim.wo.foldmethod ~= 'manual' then return end
  if not vim.wo.foldenable then vim.wo.foldenable = true end
  if vim.fn.foldlevel(state.first) == 1 and vim.fn.foldclosed(state.first) == -1 then
    local view = vim.fn.winsaveview()
    vim.cmd(('silent! %dfoldclose'):format(state.first))
    vim.fn.winrestview(view)
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
  vim.api.nvim_create_user_command('ArtikelMetadata', function() M.show() end, {
    desc = 'Bekijk technische artikelgegevens in een alleen-lezen venster',
  })
  local group = vim.api.nvim_create_augroup('ArticleMetadataFold', { clear = true })
  vim.api.nvim_create_autocmd({ 'FileType', 'BufWinEnter', 'WinEnter' }, {
    group = group,
    callback = function(event) M.attach(event.buf) end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(event) windows[tonumber(event.match)] = nil end,
  })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI', 'SafeState' }, {
    group = group, callback = keep_closed,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do M.attach(buf) end
end

return M
