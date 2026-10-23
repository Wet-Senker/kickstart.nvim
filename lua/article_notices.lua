-- Verwijderbare meldingsregels boven de artikelgrens; virtueel als veilige
-- fallback voor ongestructureerde/read-only bronnen. Geen domeinstatus.
local M = { namespace = vim.api.nvim_create_namespace 'texttools_article_notices' }
local marks, attached = {}, {}
local literal = {}

local function setup_styles()
  for name, source in pairs { TexttoolsNotice = 'Comment', TexttoolsNoticeWarning = 'WarningMsg', TexttoolsNoticeError = 'ErrorMsg' } do
    local color = vim.api.nvim_get_hl(0, { name = source, link = false })
    vim.api.nvim_set_hl(0, name, { fg = color.fg, bg = color.bg, italic = false, bold = false })
  end
end
setup_styles()
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('texttools_notice_styles', { clear = true }), callback = setup_styles,
})
M.style_namespace = vim.api.nvim_create_namespace 'texttools_notice_styles'

local function style(level)
  return level >= vim.log.levels.ERROR and 'TexttoolsNoticeError'
    or (level >= vim.log.levels.WARN and 'TexttoolsNoticeWarning' or 'TexttoolsNotice')
end

-- Alleen presentatie: de volledige melding blijft in article_activity.
-- Opgeslagen regels zonder sessiehistorie nooit willekeurig afkappen.
function M.summary(message, full_available)
  local text = tostring(message or ''):gsub('%s+', ' ')
  if text:match('^Importbewerking %(zonder AI%):') then
    return 'Import opgeschoond (zonder AI).'
  elseif text:match('^Bewerkt met Behoudend publicatieklaar maken') then
    return 'Minimaal geredigeerd (<leader>an).'
  elseif text:match('^Herschreven met Persberichten bewerken') then
    return 'Herschreven (<leader>ar).'
  elseif text:match('^Aparte krantversies aangevraagd met Persberichten bewerken') then
    return 'Krantversies aangevraagd (<leader>ar).'
  elseif text:match('^Herschreven met eigen instructie') then
    return 'Eigen instructie toegepast (<leader>ap).'
  end
  text = text:gsub('^Rubriekvorm toegepast: ', 'Rubriek: ')
    :gsub('%. Kop en vaste rubriekgegevens ingesteld%.$', '.')
    :gsub('^Kalendergegevens toegevoegd%. LET OP: ', 'LET OP: ')
    :gsub('^Tekstcheck afgerond: resultaat toegepast%. Controleer de tekst%.$', 'Taalcorrecties toegepast (<leader>ao).')
    :gsub('^Tekstcheck afgerond: geen correcties of suggesties%.$', 'Geen taalcorrecties (<leader>ao).')
    :gsub('^Tekstopmaak: ', 'Opmaak: ')
    :gsub('%. Controleer de tekst%.$', '.')
  if full_available and vim.fn.strchars(text) > 120 then
    local head = vim.fn.strcharpart(text, 0, 100):gsub('%s+%S*$', '')
    return head .. '… (<leader>kl)'
  end
  return text
end

local function boundary(line)
  return line and (line:match '^=== ARTIKEL ===%s*$' or line:match '^=== AGENDAPAGINA ===%s*$')
end

local function anchor(buf)
  local previous = marks[buf]
  if previous then
    if previous.fallback and not previous.needs_scan then return 0, true end
    local position = vim.api.nvim_buf_get_extmark_by_id(buf, M.namespace, previous.id, {})
    if #position > 0 and boundary(vim.api.nvim_buf_get_lines(buf, position[1], position[1] + 1, false)[1]) then
      return position[1], false
    end
  end
  -- Alleen bij eerste weergave of een vervangen grens zoeken. Geen domein-
  -- parser nabouwen voor oude/ruwe buffers: daar staan meldingen bovenaan.
  for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if boundary(line) then return index - 1, false end
  end
  return 0, true
end

local function width(buf)
  local available = math.max(12, vim.o.columns - 4)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    if info then available = math.min(available, math.max(12, info.width - info.textoff - 2)) end
  end
  return math.min(100, available)
end

local function wrap(text, columns)
  local lines, current = {}, ''
  for _, original in ipairs(vim.split(text, '\n', { plain = true })) do
    for _, word in ipairs(vim.split(original, '%s+', { trimempty = true })) do
      if current ~= '' and vim.fn.strdisplaywidth(current .. word) > columns then
        lines[#lines + 1], current = vim.trim(current), ''
      end
      -- Ook lange paden/URL's passen zonder een instructie rechts af te kappen.
      for _, character in ipairs(vim.fn.split(word, '\\zs')) do
        if vim.fn.strdisplaywidth(current .. character) > columns then
          lines[#lines + 1], current = current, ''
        end
        current = current .. character
      end
      current = current .. ' '
    end
    lines[#lines + 1], current = vim.trim(current), ''
  end
  return lines
end

function M.hide(buf)
  if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1) end
  marks[buf] = nil
end

-- Bewaar onveranderde kopregels/extmarks wanneer een client de artikelbody
-- of een staartsectie vervangt. Anders werden gekopieerde oude meldingsregels
-- na een volledige set_lines onherleidbaar en niet meer opgeruimd.
function M.replace_content(buf, lines)
  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Een gedeelde documentactie kan vóór én na het meldingenblok wijzigen.
  -- Alleen exact overgenomen, vóór de actie nog geldige meldingen herbinden;
  -- een door de redacteur weggehaalde/bewerkte regel nooit herstellen.
  local tracked, used, last = {}, {}, nil
  for index, line in ipairs(lines) do if boundary(line) then last = index; break end end
  for _, entry in pairs(literal[buf] and literal[buf].entries or {}) do
    local at = vim.api.nvim_buf_get_extmark_by_id(buf, M.line_namespace, entry.mark, { details = true })
    if #at > 0 and not at[3].invalid and before[at[1] + 1] == entry.text then
      for index = 1, (last or 1) - 1 do
        if not used[index] and lines[index] == entry.text then
          tracked[entry], used[index] = index - 1, true
          break
        end
      end
    end
  end
  local first, old_end, new_end = 0, #before, #lines
  while first < old_end and first < new_end and before[first + 1] == lines[first + 1] do first = first + 1 end
  while old_end > first and new_end > first and before[old_end] == lines[new_end] do
    old_end, new_end = old_end - 1, new_end - 1
  end
  if first == old_end and first == new_end then return end
  local replacement = {}
  for index = first + 1, new_end do replacement[#replacement + 1] = lines[index] end
  vim.api.nvim_buf_set_lines(buf, first, old_end, false, replacement)
  for entry, at in pairs(tracked) do
    entry.mark = vim.api.nvim_buf_set_extmark(buf, M.line_namespace, at, 0, {
      id = entry.mark, end_row = at + 1, end_col = 0, invalidate = true, undo_restore = false,
      line_hl_group = entry.style or 'TexttoolsNotice', right_gravity = true,
    })
  end
end

local function show_virtual(buf, issues, changed)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
  local notices = {}
  for _, issue in pairs(issues or {}) do notices[#notices + 1] = issue end
  if #notices == 0 then
    if marks[buf] then M.hide(buf) end
    return
  end
  table.sort(notices, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    return a.id < b.id
  end)
  local columns, row, fallback = width(buf), anchor(buf)
  local previous, ids = marks[buf], {}
  for _, notice in ipairs(notices) do ids[#ids + 1] = notice.id end
  if previous and previous.width == columns and vim.deep_equal(previous.ids, ids) then
    -- Tekstbewerkingen verplaatsen het extmark zelf. Alleen een vervangen
    -- grens vraagt een nieuwe tekenpositie; niet iedere toets opnieuw wrappen.
    if previous.row ~= row then
      vim.api.nvim_buf_set_extmark(buf, M.namespace, row, 0, {
        id = previous.id, virt_lines = previous.rows, virt_lines_above = row > 0, right_gravity = false,
      })
      previous.row = row
    end
    previous.fallback, previous.needs_scan = fallback, false
    return
  end
  local rows = { { { '', 'Normal' } } }
  local function append(message, style)
    for _, line in ipairs(wrap(message, columns)) do rows[#rows + 1] = { { line, style } } end
  end
  for index = 1, math.min(3, #notices) do
    local notice = notices[index]
    local summary = M.summary(notice.message, true)
    local prefix = notice.level >= vim.log.levels.ERROR and 'FOUT: '
      or (notice.level >= vim.log.levels.WARN and 'LET OP: ' or '')
    if summary:find('LET OP:', 1, true) or summary:match('^FOUT:') then prefix = '' end
    local notice_style = style(notice.level)
    local lines = wrap(prefix .. summary, columns)
    local maximum = math.min(8, #lines)
    for line = 1, maximum do rows[#rows + 1] = { { lines[line], notice_style } } end
    if #lines > maximum then
      append('Uitleg: <leader>kl.', 'TexttoolsNotice')
    end
  end
  if #notices > 3 then
    append(('%d meer · <leader>kl.'):format(#notices - 3), 'TexttoolsNoticeWarning')
  end
  rows[#rows + 1] = { { '', 'Normal' } }
  if not previous or previous.row ~= row or not vim.deep_equal(previous.rows, rows) then
    local id = vim.api.nvim_buf_set_extmark(buf, M.namespace, row, 0, {
      id = previous and previous.id or nil,
      -- Virtuele regels bóven bufferregel 1 zijn in Neovims gewone viewport
      -- onzichtbaar. Zonder kopregels daarom net onder de eerste/grensregel.
      virt_lines = rows, virt_lines_above = row > 0, right_gravity = false,
    })
    marks[buf] = { id = id, row = row, rows = rows }
  end
  marks[buf].width, marks[buf].ids = columns, ids
  marks[buf].fallback, marks[buf].needs_scan = fallback, false
  if not attached[buf] then
    attached[buf] = vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first, _, last)
        local mark = marks[buf]
        if not mark then return end
        if mark.fallback then
          for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, first, last, false)) do
            if boundary(line) then mark.needs_scan = true; break end
          end
        end
        changed()
      end,
      on_reload = function()
        if marks[buf] then marks[buf].needs_scan = true; changed() end
      end,
      on_detach = function() attached[buf], marks[buf] = nil, nil end,
    })
  end
end

-- Echte, verwijderbare werkregels. Het expliciete Melding:-contract wordt
-- door Python alleen boven een artikelgrens geaccepteerd en nooit gepubliceerd.
M.line_namespace = vim.api.nvim_create_namespace 'texttools_notice_lines'

local function header_start(lines, last)
  if lines[1] and vim.trim(lines[1]) == '---' then
    for index = 2, last - 1 do
      if vim.trim(lines[index]) == '---' then return index + 1 end
    end
    return last -- Geen onvolledige YAML proberen te formatteren.
  end
  return 1
end

-- Alleen representatieruis uit vergelijkingssnapshots halen. Zonder expliciete
-- grens is "Melding:" mogelijk gewone bron-/artikeltekst en blijft ze intact.
function M.content_lines(lines)
  local last
  for index, line in ipairs(lines) do if boundary(line) then last = index; break end end
  if not last then return lines end
  local first = header_start(lines, last)
  local clean = {}
  for index, line in ipairs(lines) do
    -- Witruimte tussen instellingen en meldingen is eveneens presentatie.
    -- YAML (ook meerregelige waarden) en alle artikelwitruimte blijven exact.
    if index < first or index >= last
      or (not line:match('^%s*$') and not line:lower():match('^%s*melding%s*:')) then
      clean[#clean + 1] = line
    end
  end
  return clean
end

local function position(buf, id)
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, M.line_namespace, id, { details = true })
  if #mark == 0 or mark[3].invalid then return nil end
  return mark[1]
end

local function line_text(notice)
  local message = M.summary(notice.message, true)
  if notice.level >= vim.log.levels.ERROR then
    if not message:match('^FOUT:') then message = 'FOUT: ' .. message end
  elseif notice.level >= vim.log.levels.WARN and not message:find('LET OP:', 1, true) then
    message = 'LET OP: ' .. message
  end
  return 'Melding: ' .. message
end

local function line_mark(buf, at, style, id)
  return vim.api.nvim_buf_set_extmark(buf, M.line_namespace, at, 0, {
    id = id, end_row = at + 1, end_col = 0, invalidate = true, undo_restore = false,
    line_hl_group = style, right_gravity = true,
  })
end

local function highlight_header(buf, lines, first)
  vim.api.nvim_buf_clear_namespace(buf, M.style_namespace, 0, -1)
  for index = first, #lines do
    local text = lines[index]
    if text:lower():match('^%s*melding%s*:') then
      local level = text:find('Melding: FOUT:', 1, true) and vim.log.levels.ERROR
        or (text:find('LET OP:', 1, true) and vim.log.levels.WARN or vim.log.levels.INFO)
      vim.api.nvim_buf_set_extmark(buf, M.style_namespace, index - 1, 0, {
        end_row = index, end_col = 0, hl_group = style(level), hl_mode = 'replace', priority = 250,
      })
    end
  end
end

-- Een tekstherstel is geen nieuwe redactieopdracht. Onthoud alleen de twee
-- geschiedenisnummers wanneer de buffer werkelijk verandert; geen polling of
-- artikelkopieën. Nieuwe edits krijgen altijd een nummer boven de oude takken.
local function observe_history(buf, state)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local previous = state.history
  if previous and previous.tick == tick then return end
  local current = vim.api.nvim_buf_call(buf, vim.fn.changenr)
  if previous then
    if current ~= previous.current then state.restoring = current <= previous.last end
    state.history = { tick = tick, current = current, last = math.max(previous.last, current) }
  else
    local history = vim.api.nvim_buf_call(buf, vim.fn.undotree)
    state.history = { tick = tick, current = current, last = history.seq_last }
  end
end

-- Uitsluitend indeling van het expliciete editor-kopblok. Geen controleregels
-- herkennen/valideren of Python-tabellen dupliceren; alle andere regels houden
-- hun tekst en volgorde. YAML en artikelbody worden nooit herschreven.
local function organize_header(buf, state)
  local row = position(buf, state.boundary)
  if not row then return end
  local before = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  local first = header_start(before, row + 1)
  local controls, notices, positions = {}, {}, {}
  for index = first, row do
    local line = before[index]
    if line:lower():match('^%s*melding%s*:') then
      local message = line:match('^%s*[Mm][Ee][Ll][Dd][Ii][Nn][Gg]%s*:%s*(.*)$')
      notices[#notices + 1] = { text = 'Melding: ' .. M.summary(message, false), index = index }
    elseif not line:match('^%s*$') then
      controls[#controls + 1] = { text = line, index = index }
    end
  end
  if #notices == 0 then
    vim.api.nvim_buf_clear_namespace(buf, M.style_namespace, 0, -1)
    return
  end
  local after = {}
  for index = 1, first - 1 do after[#after + 1] = before[index] end
  if #after > 0 then after[#after + 1] = '' end
  for _, block in ipairs { controls, notices } do
    for _, item in ipairs(block) do
      after[#after + 1] = item.text
      positions[item.index] = #after
    end
    if #block > 0 then after[#after + 1] = '' end
  end
  if vim.deep_equal(before, after) then
    highlight_header(buf, before, first)
    return
  end
  local tracked, cursors = {}, {}
  for _, entry in pairs(state.entries) do
    local at = position(buf, entry.mark)
    if at and before[at + 1] == entry.text then tracked[entry] = positions[at + 1] end
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local cursor = vim.api.nvim_win_get_cursor(win)
    if positions[cursor[1]] then cursors[win] = { positions[cursor[1]], cursor[2] } end
  end
  -- Alleen het gewijzigde kopbereik vervangen; onveranderde extmarks blijven.
  local prefix, old_end, new_end = 0, #before, #after
  while prefix < old_end and prefix < new_end and before[prefix + 1] == after[prefix + 1] do prefix = prefix + 1 end
  while old_end > prefix and new_end > prefix and before[old_end] == after[new_end] do
    old_end, new_end = old_end - 1, new_end - 1
  end
  local replacement = {}
  for index = prefix + 1, new_end do replacement[#replacement + 1] = after[index] end
  vim.api.nvim_buf_set_lines(buf, prefix, old_end, false, replacement)
  for entry, at in pairs(tracked) do
    entry.text = after[at]
    entry.mark = line_mark(buf, at - 1, entry.style or 'TexttoolsNotice', entry.mark)
  end
  for win, cursor in pairs(cursors) do vim.api.nvim_win_set_cursor(win, cursor) end
  highlight_header(buf, after, header_start(after, #after + 1))
end

function M.show(buf, issues, changed, may_edit)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return end
  local state = literal[buf]
  if not state and not next(issues or {}) then
    if marks[buf] then M.hide(buf) end
    -- Ook opgeslagen meldingen kunnen na heropenen tussen de gegevens staan.
    -- Geen geschiedenis of domeinstatus uit hun vrije tekst reconstrueren.
    if may_edit == false or not vim.bo[buf].modifiable or vim.bo[buf].readonly then return end
    local found, lines, finished = false, {}, false
    local total = vim.api.nvim_buf_line_count(buf)
    for start = 0, total - 1, 128 do
      for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, start, math.min(start + 128, total), false)) do
        lines[#lines + 1] = line
        if boundary(line) then finished = true; break end
      end
      if finished then break end
    end
    if not finished then return end
    for index = header_start(lines, #lines), #lines - 1 do
      if lines[index]:lower():match('^%s*melding%s*:') then found = true; break end
    end
    if not found then return end
  end
  local row = state and position(buf, state.boundary)
  if row and not boundary(vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]) then row = nil end
  if not row then
    if not state then
      local fallback
      row, fallback = anchor(buf)
      if fallback then row = nil end
    else
      for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if boundary(line) then row = index - 1; break end
      end
    end
  end
  -- Ruwe import krijgt geen verzonnen grens. Read-only publicatiereviews blijven
  -- read-only; daar is de bestaande virtuele weergave de veilige fallback.
  if not row or not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    show_virtual(buf, issues, changed)
    return
  end
  M.hide(buf)
  if not state then
    state = { entries = {}, dismissed = {}, editing = false, rendered_notices = {} }
    literal[buf] = state
    state.boundary = vim.api.nvim_buf_set_extmark(buf, M.line_namespace, row, 0, {})
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function(_, _, _, first)
        if state.editing then return end
        -- Ook body-edits observeren zonder de kop opnieuw te renderen. Anders
        -- lijkt undo na zo'n edit op nieuw werk als geen refresh ertussen kwam.
        observe_history(buf, state)
        local at = position(buf, state.boundary)
        if not at or first <= at then changed() end
      end,
      on_reload = function()
        state.history, state.restoring = nil, false
        changed()
      end,
      on_detach = function() literal[buf] = nil end,
    })
  else
    state.boundary = vim.api.nvim_buf_set_extmark(buf, M.line_namespace, row, 0, { id = state.boundary })
  end
  observe_history(buf, state)
  -- Wijzig geen bronrevisie terwijl een achtergrondtaak met die revisie werkt.
  -- Na de laatste taak volgt automatisch de bestaande refresh, zonder wachten.
  if may_edit == false then return end
  local current, ordered, signature = {}, {}, {}
  for _, notice in pairs(issues or {}) do
    current[notice.id] = notice
    ordered[#ordered + 1] = notice
    signature[notice.id] = { notice.message, notice.level }
  end
  table.sort(ordered, function(a, b) return a.id < b.id end)
  -- Na undo/redo ook bij BufEnter/resize/logboekdetails de herstelde tekst
  -- ongemoeid laten. Alleen een echt nieuw resultaat mag weer muteren.
  if state.restoring and vim.deep_equal(signature, state.rendered_notices) then
    local header = vim.api.nvim_buf_get_lines(buf, 0, row, false)
    highlight_header(buf, header, header_start(header, row + 1))
    return
  end
  state.restoring = false
  state.editing = true
  for id, entry in pairs(state.entries) do
    local at = position(buf, entry.mark)
    local same = at and vim.api.nvim_buf_get_lines(buf, at, at + 1, false)[1] == entry.text
    -- Undo kan de echte regel herstellen zonder zijn ongeldig gemaakte
    -- presentatie-extmark. Bind alleen exact dezelfde tekst opnieuw.
    if not same then
      local last = position(buf, state.boundary)
      local header = last and vim.api.nvim_buf_get_lines(buf, 0, last, false) or {}
      for index = header_start(header, #header + 1), #header do
        if header[index] == entry.text then
          at, same = index - 1, true
          entry.mark = line_mark(buf, at, entry.style or 'TexttoolsNotice', entry.mark)
          break
        end
      end
    end
    if not same then
      -- dd of een eigen tekstbewerking is een bewuste UI-afwijzing, geen
      -- domeingoedkeuring. Dezelfde melding wordt niet opnieuw ingevoegd.
      state.dismissed[id] = true
    elseif not current[id] then
      vim.api.nvim_buf_set_lines(buf, at, at + 1, false, {})
    end
    if not same or not current[id] then
      vim.api.nvim_buf_del_extmark(buf, M.line_namespace, entry.mark)
      state.entries[id] = nil
    end
  end
  for _, notice in ipairs(ordered) do
    if not state.entries[notice.id] and not state.dismissed[notice.id] then
      local at = position(buf, state.boundary)
      if at then
        local text = line_text(notice)
        vim.api.nvim_buf_set_lines(buf, at, at, false, { text })
        local notice_style = style(notice.level)
        local mark = line_mark(buf, at, notice_style)
        state.entries[notice.id] = { mark = mark, text = text, style = notice_style }
      end
    end
  end
  for id in pairs(state.dismissed) do if not current[id] then state.dismissed[id] = nil end end
  organize_header(buf, state)
  state.editing = false
  state.rendered_notices = signature
  observe_history(buf, state)
end

return M
