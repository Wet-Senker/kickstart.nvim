-- Presentation only. Python validates and persists every publication exclusion.
local M = {}
local notices = require 'texttools_notify'

local function flat(value)
  if value == nil or value == vim.NIL then return '' end
  return tostring(value):gsub('%s+', ' ')
end
local function nonempty(...)
  for index = 1, select('#', ...) do
    local value = flat(select(index, ...))
    if vim.trim(value) ~= '' then return value end
  end
end
local function date(value, today)
  local text = flat(value)
  local year, month, day, rest = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$')
  if year then text = day .. '-' .. month .. '-' .. year .. rest
  else day, month, year = text:match('^(%d%d)%-(%d%d)%-(%d%d%d%d)') end
  local ty, tm, td = today:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  if not year or not ty then return text end
  local function stamp(y, m, d)
    local ok, result = pcall(os.time, { year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    if not ok or not result or os.date('%Y-%m-%d', result) ~= y .. '-' .. m .. '-' .. d then return nil end
    return result
  end
  local target, reference = stamp(year, month, day), stamp(ty, tm, td)
  if not target or not reference then return text end
  -- Lokale kalenderdagen, afgerond vanaf de middag: ook 23-/25-uursdagen
  -- bij zomer-/wintertijd zijn één dag, niet nul of twee.
  local days = math.floor(os.difftime(target, reference) / 86400 + 0.5)
  local relative = ({ [0] = 'vandaag', [-1] = 'gisteren', [1] = 'morgen' })[days]
    or (days < 0 and (math.abs(days) .. ' dagen geleden') or ('over ' .. days .. ' dagen'))
  return text .. ' (' .. relative .. ')'
end

function M.show(report, callback, options)
  options = options or {}
  local simple = options.simple_review == true
  local today = options.today or os.date('%Y-%m-%d')
  local function display_date(value) return date(value, today) end
  local function compact_date(value)
    return display_date(value):gsub(' om (%d%d?)[%.:](%d%d) uur', ', %1.%2')
  end
  local entries, choices = {}, {}
  for _, candidate in ipairs(report.candidates or {}) do
    for _, variant in ipairs(candidate.variants or {}) do
      entries[#entries + 1] = { candidate = candidate, variant = variant,
        target = variant.review_target, selectable = variant.review_selectable }
      if variant.review_target and variant.review_decision then
        choices[variant.review_target.id] = variant.review_decision
      end
    end
  end
  for _, saved in ipairs(report.saved_selections or {}) do
    if saved.decision == 'duplicate' or saved.source == report.review_source then
      choices[saved.id] = saved.decision
    end
    entries[#entries + 1] = { target = saved, selectable = true, variant = {
      edition = saved.edition, headline = saved.headline, editor_url = saved.url,
      kind = saved.kind, text = (saved.existing or {}).text,
      display_date_short = (saved.existing or {}).display_date_short,
    }, candidate = { kind = saved.kind }, previous = true }
  end
  for _, offer in ipairs(report.agenda_only_offers or {}) do
    if offer.selected then choices[offer.id] = 'different' end
    entries[#entries + 1] = { offer = offer, variant = { edition = offer.edition, headline = offer.title } }
  end
  local editions = require 'editions'
  for _, entry in ipairs(entries) do
    local v = entry.variant
    entry.publication = nonempty(v.publication) or editions.name(nonempty(v.edition)) or 'Onbekende krant'
  end
  table.sort(entries, function(a, b)
    if a.publication ~= b.publication then return a.publication < b.publication end
    return flat(a.variant.headline) < flat(b.variant.headline)
  end)
  local groups, by_scope = {}, {}
  for _, entry in ipairs(entries) do
    local v = entry.variant
    local target = entry.target or {}
    local kind = target.kind or v.kind or entry.candidate and entry.candidate.kind or 'web'
    local edition = nonempty(target.edition, v.edition, v.publication)
    local event = type(target.source_event) == 'table' and target.source_event
      or (entry.candidate or {}).source_event
    -- Use the core's source-event identity, never a title or date on its own.
    -- Old agenda reports without that identity keep their separate choices.
    local scope
    if not entry.offer and edition and kind == 'web' then
      scope = vim.json.encode { kind, edition, entry.selectable == true }
    elseif not entry.offer and edition and type(event) == 'table' and nonempty(event.ref) then
      scope = vim.json.encode { kind, edition, entry.selectable == true, event.structured == true, event.ref, flat(event.date) }
    end
    local group = scope and by_scope[scope]
    if not group then
      -- Koppen zijn het primaire beoordelingsmateriaal en staan daarom meteen
      -- open. De groepsregel blijft beschikbaar voor één gezamenlijk besluit.
      group = { kind = kind, publication = entry.publication, entries = {}, expanded = true }
      groups[#groups + 1] = group
      if scope then by_scope[scope] = group end
    end
    group.entries[#group.entries + 1] = entry
  end
  local function group_choice(group)
    local all_different = true
    for _, entry in ipairs(group.entries) do
      local choice = entry.target and choices[entry.target.id]
      if choice == 'duplicate' then return choice, entry end
      if choice ~= 'different' then all_different = false end
    end
    if all_different then return 'different' end
  end
  local function marker(choice)
    return choice == 'duplicate' and '[=]' or choice == 'different' and '[≠]' or '[ ]'
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'Pubble doublurecontrole')
  local win, rows, clicks, done, detail, detail_row, applying = nil, {}, {}, false, nil, nil, false
  local function finish(ok)
    if done then return end
    done = true
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    callback(ok)
  end
  local function selected()
    return rows[vim.api.nvim_win_get_cursor(win)[1]]
  end
  local function render()
    rows = {}
    clicks = {}
    local lines = {}
    local function add_no_duplicate_button(row, group, choice)
      if not group.entries[1].selectable then return end
      local label = choice == 'different' and '[keuze wissen]' or '[geen doublures]'
      local prefix = lines[row] .. '  '
      lines[row] = prefix .. label
      clicks[row] = {
        -- getmousepos().column is a one-based byte index, also bij [−]/[≠].
        first = #prefix + 1,
        last = #lines[row],
        group = group,
      }
    end
    if detail then
      local v = detail.variant
      lines = { flat(v.headline), '',
        'Krant: ' .. flat(v.publication or v.edition),
        'Publicatie: ' .. display_date(nonempty(v.display_date_short, v.display_date_label)),
        'Aangemaakt: ' .. display_date(nonempty(v.created_date_short, v.created_date_label))
          .. ' · ' .. (nonempty(v.created_by_label, v.created_by) or 'maker onbekend'),
        'Pubble: ' .. flat(v.editor_url), '',
        flat(v.location), flat(v.city), '' }
      local content = type(v.text) == 'string' and v.text ~= '' and v.text or v.lead
      if type(content) ~= 'string' or content == '' then content = 'Geen tekst beschikbaar; gebruik o voor Pubble.' end
      vim.list_extend(lines, vim.split(content, '\n', { plain = true }))
      vim.list_extend(lines, { '', 'Enter / q  Terug' })
    else
      lines = {}
      for _, message in ipairs(report.errors or {}) do lines[#lines + 1] = 'LET OP: ' .. flat(message) end
      local previous
      for _, group in ipairs(groups) do
        local entry = group.entries[1]
        if group.publication ~= previous then
          if #lines > 0 then lines[#lines + 1] = '' end
          lines[#lines + 1] = group.publication; previous = group.publication
        end
        if simple then
          for _, hit in ipairs(group.entries) do
            if not hit.offer then
              local v = hit.variant
              lines[#lines + 1] = compact_date(nonempty(v.display_date_short, v.display_date_label))
                .. '  ' .. flat(v.headline)
              rows[#lines] = { group = group, entry = hit }
            end
          end
        elseif entry.offer then
          lines[#lines + 1] = (choices[entry.offer.id] and '[+]' or '[ ]')
            .. ' Alleen agenda: ' .. flat(entry.offer.title) .. ' — geen agendadoublure gevonden [a]'
          rows[#lines] = { entry = entry }
        else
          local kind = group.kind == 'agenda' and 'Agenda:' or 'Web:'
          local comparison = (entry.candidate or {}).comparison
          if type(comparison) ~= 'table' then comparison = (entry.target or {}).comparison end
          if type(comparison) ~= 'table' then comparison = nil end
          local label = ('%-7s '):format(kind)
          local readonly = entry.selectable and '' or '  (alleen bekijken: geen gekozen doelkrant)'
          local choice, confirmed = group_choice(group)
          if #group.entries > 1 then
            local source = group.kind == 'agenda' and comparison
              and (compact_date(comparison.date) .. '  ' .. flat(comparison.headline) .. '  ·  ') or ''
            lines[#lines + 1] = marker(choice) .. ' ' .. label .. source
              .. #group.entries .. ' treffers  [' .. (group.expanded and '−' or '+') .. ']' .. readonly
            rows[#lines] = { group = group }
            add_no_duplicate_button(#lines, group, choice)
          end
          if #group.entries == 1 or group.expanded then
            for _, hit in ipairs(group.entries) do
              local v = hit.variant
              local prefix = #group.entries == 1 and (marker(choice) .. ' ' .. label)
                or (hit == confirmed and '    → ' or '      ')
              lines[#lines + 1] = prefix .. compact_date(nonempty(v.display_date_short, v.display_date_label))
                .. '  ' .. flat(v.headline)
                .. (nonempty(v.created_by_label, v.created_by) and (' · ' .. nonempty(v.created_by_label, v.created_by)) or '')
                .. (hit.previous and '  (eerdere keuze)' or '') .. (#group.entries == 1 and readonly or '')
              rows[#lines] = { group = group, entry = hit }
              if #group.entries == 1 then add_no_duplicate_button(#lines, group, choice) end
            end
            if #group.entries == 1 and comparison then
              lines[#lines + 1] = '    Jouw bericht: ' .. compact_date(comparison.date) .. '  ' .. flat(comparison.headline)
              rows[#lines] = { group = group, entry = entry }
            end
          end
        end
      end
      if simple then
        local continuation = options.continue_send and 'verzenden' or 'verder'
        lines[#lines + 1] = ''
        lines[#lines + 1] = '[Geen doublure · ' .. continuation .. ']   [Wel doublure · stoppen]'
        local row = #lines
        local last = assert(lines[row]:find(']', 1, true))
        clicks[row] = { first = 1, last = last, decision = 'different' }
        clicks[row].duplicate_first = last + 4
        lines[#lines + 1] = 'n  Geen doublure    m  Wel doublure    Enter  Tekst    o  Pubble'
      else
      vim.list_extend(lines, { '', 'Enter / dubbelklik  Tekst; groepsregel in-/uitklappen   o  Pubble',
        'Klik [geen doublures] of druk n   m  Wel doublure',
        options.continue_send and 'q  Keuzes bewaren en doorgaan met verzenden'
          or 'q  Keuzes bewaren en sluiten' })
      if #(report.agenda_only_offers or {}) > 0 then
        lines[#lines + 1] = 'a  Alleen agenda aan/uit (bij webdoublure)'
      end
      end
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    if win and vim.api.nvim_win_is_valid(win) then
      local maximum = math.max(4, vim.o.lines - 6)
      local height = vim.api.nvim_win_text_height(win, {
        start_row = 0, end_row = math.min(#lines, maximum) - 1,
      }).all
      vim.api.nvim_win_set_height(win, math.min(math.max(1, height), maximum))
    end
  end
  local function close_detail()
    detail = nil
    render()
    vim.api.nvim_win_set_cursor(win, { detail_row, 0 })
  end
  local function select_hit(group)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    group.expanded = true
    render()
    vim.api.nvim_win_set_cursor(win, { row + 1, 0 })
  end
  local apply
  local function toggle(value)
    if applying or detail then return end
    local row = selected()
    local group = row and row.group
    if not group or not group.entries[1].selectable or not group.entries[1].target then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    local choice, confirmed = group_choice(group)
    if value == 'different' then
      for _, hit in ipairs(group.entries) do
        if hit.target then choices[hit.target.id] = choice ~= 'different' and 'different' or nil end
      end
    else
      local hit = row.entry or confirmed
      if not hit then
        select_hit(group)
        return
      end
      if not hit.target then return end
      local duplicate = choices[hit.target.id] ~= 'duplicate'
      for _, member in ipairs(group.entries) do
        if member.target and choices[member.target.id] == 'duplicate' then choices[member.target.id] = nil end
      end
      if duplicate then choices[hit.target.id] = 'duplicate' end
    end
    render()
    vim.api.nvim_win_set_cursor(win, cursor)
    if options.continue_send and value == 'different' and #(report.agenda_only_offers or {}) == 0 then
      local count = 0
      for _, decision_group in ipairs(groups) do
        local item = decision_group.entries[1]
        if item.selectable and item.target then
          count = count + 1
          if group_choice(decision_group) ~= 'different' then return end
        end
      end
      if count > 0 then apply() end
    end
  end
  apply = function()
    if detail then close_detail(); return end
    if applying then return end
    if options.is_current and not options.is_current() then finish(false); return end
    if #(report.errors or {}) > 0 or report.history_complete == false then
      notices.notify('Doublurecontrole is onvolledig; keuzes zijn niet opgeslagen. Controleer opnieuw vóór verzending.',
        vim.log.levels.ERROR)
      return
    end
    if not options.on_apply then
      notices.notify('Geen veilige opslagactie beschikbaar; werk Texttools en Neovim bij.', vim.log.levels.ERROR)
      return
    end
    applying = true
    options.on_apply(report, choices, function(ok)
      applying = false
      if ok then report.selection_applied = true; finish(true) end
    end)
  end
  local function decide(value)
    if not simple then toggle(value); return end
    if applying or detail then return end
    if options.is_current and not options.is_current() then finish(false); return end
    if value == 'duplicate' then
      report.article_duplicate = true
      finish(false)
      return
    end
    for _, entry in ipairs(entries) do
      if entry.selectable and entry.target then choices[entry.target.id] = 'different' end
    end
    apply()
  end
  win = vim.api.nvim_open_win(buf, true, { relative = 'editor',
    width = math.min(110, math.max(20, vim.o.columns - 4)),
    height = math.min(math.max(16, #entries * 3 + 11), math.max(8, vim.o.lines - 6)),
    row = 2, col = 1, style = 'minimal', border = 'rounded', title = ' Mogelijke doublures ', title_pos = 'center' })
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  render()
  for row = 1, vim.api.nvim_buf_line_count(buf) do
    if rows[row] then vim.api.nvim_win_set_cursor(win, { row, 0 }); break end
  end
  vim.keymap.set('n', 'm', function() decide('duplicate') end, { buffer = buf })
  vim.keymap.set('n', 'n', function() decide('different') end, { buffer = buf })
  local function mouse_target(mouse)
    if applying or detail or mouse.winid ~= win or not mouse.line then return false end
    if rows[mouse.line] then vim.api.nvim_win_set_cursor(win, { mouse.line, 0 }) end
    local click = clicks[mouse.line]
    local column = tonumber(mouse.column) or 0
    if simple and click then
      if column >= click.first and column <= click.last then decide('different')
      elseif column >= click.duplicate_first then decide('duplicate') end
      return false
    end
    return click ~= nil and column >= click.first and column <= click.last
  end
  vim.keymap.set('n', '<LeftMouse>', function()
    if mouse_target(vim.fn.getmousepos()) then toggle('different') end
  end, { buffer = buf })
  vim.keymap.set('n', 'a', function()
    if applying or detail then return end
    local row = selected()
    local entry = row and row.entry
    if not entry or not entry.offer then return end
    if choices[entry.offer.id] then choices[entry.offer.id] = nil
    else choices[entry.offer.id] = 'different' end
    local cursor = vim.api.nvim_win_get_cursor(win)
    render()
    vim.api.nvim_win_set_cursor(win, cursor)
  end, { buffer = buf })
  vim.keymap.set('n', 'q', function()
    if simple then
      if detail then close_detail() else finish(false) end
    else apply() end
  end, { buffer = buf })
  vim.keymap.set('n', '<C-c>', function() if not applying then finish(false) end end, { buffer = buf })
  local function inspect()
    if applying then return end
    if detail then close_detail(); return end
    local row = selected()
    if not row or not row.group then return end
    local cursor = vim.api.nvim_win_get_cursor(win)
    if row.entry then
      detail, detail_row = row.entry, cursor[1]
    else
      row.group.expanded = not row.group.expanded
    end
    render()
    vim.api.nvim_win_set_cursor(win, detail and { 1, 0 } or cursor)
  end
  vim.keymap.set('n', '<CR>', inspect, { buffer = buf })
  vim.keymap.set('n', '<2-LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse_target(mouse) then return end
    if mouse.winid == win and mouse.line then
      vim.api.nvim_win_set_cursor(win, { mouse.line, math.max(0, (mouse.column or 1) - 1) })
      inspect()
    end
  end, { buffer = buf })
  vim.keymap.set('n', 'o', function()
    local row = selected()
    local entry = detail or row and row.entry
    if not entry and row and row.group then
      local _, confirmed = group_choice(row.group)
      if not confirmed then select_hit(row.group); return end
      entry = confirmed
    end
    local url = entry and nonempty(entry.variant.editor_url)
    if url then require('ordered_browser').open_urls { url } end
  end, { buffer = buf })
  require('context_help').register(buf, function() return {
    title = 'Doublurekeuzes', status = simple
      and 'n beoordeelt alle treffers als geen doublure en gaat verder. m stopt de lopende artikelactie.'
      or options.continue_send
      and 'q bewaart de keuzes en hervat deze verzending. Alles geen doublure: automatisch doorgaan.'
      or 'Keuzes worden pas met q toegepast; dit publiceert niets.',
    sections = { { heading = 'Bediening', lines = simple and {
      'n of Geen doublure: beoordeel alle selecteerbare treffers als geen doublure en ga verder.',
      'm of Wel doublure: stop de lopende artikelactie voor het hele artikel.',
      'Enter: bekijk de tekst. o: open de treffer in Pubble.',
      'q of Control+c: sluit de controle. Gebruik <leader>ad voor keuzes per editie of agenda-item.',
    } or {
      'Trefferkoppen staan standaard open; Enter op een groepsregel klapt ze in of uit.',
      'Klik [geen doublures] of druk n: geen doublure voor deze editie of dit agenda-item bij deze editie.',
      'm: wel doublure. Bij meerdere treffers kies je welk bestaand bericht het is.',
      'Enter op een treffer: tekst bekijken of terug. o: bestaande treffer openen in Pubble.',
      options.continue_send and 'q: opslaan en doorgaan met deze verzending.'
        or 'q: opslaan en verder bewerken. Daarna bewust <leader>aw voor verzending.',
      'Control+c: sluit zonder nieuwe keuzes te bewaren; eerder opgeslagen keuzes blijven staan.',
      'Bij uitstellen wacht de automatische voorbereiding van het agenda-item.',
      'Een verwijderde meldingsregel wist geen opgeslagen doublurekeuze; heropen de controle.',
    } } },
  } end)
  vim.api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function() if not done then finish(false) end end })
end

return M
