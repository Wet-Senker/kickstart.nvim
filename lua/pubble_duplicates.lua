local M = {}
local notifications = require('texttools_notify')

local function trim_text(value, maximum)
  local text = vim.trim(tostring(value or '')):gsub('%s+', ' ')
  if #text <= maximum then return text end
  return text:sub(1, maximum - 1):gsub('%s+$', '') .. '…'
end

local function publications(candidate)
  if type(candidate.publications) ~= 'table' then return 'onbekende krant' end
  return table.concat(candidate.publications, ' + ')
end

local function variant_lines(variant)
  local created = variant.created_date_label or 'aanmaakdatum onbekend'
  local creator = variant.created_by or 'maker onbekend'
  return {
    ('   %s'):format(variant.publication or variant.edition or 'Onbekende krant'),
    ('     Publicatiedatum: %s'):format(variant.display_date_label or 'datum onbekend'),
    ('     Aangemaakt: %s door %s'):format(created, creator),
    ('     Pubble: %s'):format(variant.editor_url or 'link onbekend'),
  }
end

function M.report_lines(result, options)
  options = options or {}
  local candidates = type(result) == 'table' and result.candidates or {}
  local singular = #candidates == 1
  local lines = {
    singular and 'MOGELIJKE DOUBLURE' or 'MOGELIJKE DOUBLURES',
    '',
    singular
        and 'Dit artikel lijkt op een bericht dat al in Pubble staat.'
      or ('Dit artikel lijkt op %d berichten die al in Pubble staan.'):format(#candidates),
    '',
  }
  local ranges = {}
  for index, candidate in ipairs(candidates) do
    local first = #lines + 1
    table.insert(lines, ('%d. %s'):format(index, candidate.headline or 'Zonder kop'))
    table.insert(lines, ('   Sites: %s'):format(publications(candidate)))
    for _, variant in ipairs(candidate.variants or {}) do
      vim.list_extend(lines, variant_lines(variant))
    end
    table.insert(lines, '')
    if singular then
      table.insert(lines, 'VOLLEDIGE TEKST')
      table.insert(lines, '')
      vim.list_extend(lines, vim.split(candidate.text or candidate.lead or '', '\n', { plain = true }))
    else
      table.insert(lines, '   Lead: ' .. trim_text(candidate.lead, 500))
    end
    table.insert(lines, '')
    ranges[#ranges + 1] = { first = first, last = #lines, candidate = candidate }
  end
  local approve_label = options.approve_label or 'toch verzenden'
  table.insert(lines, 'o = openen in Pubble  •  t/Enter = volledige tekst  •  v = '
    .. approve_label .. '  •  q = annuleren')
  return lines, ranges
end

local function candidate_at_cursor(ranges, row)
  local nearest
  for _, range in ipairs(ranges) do
    if row >= range.first and row <= range.last then return range.candidate end
    if row >= range.first then nearest = range.candidate end
  end
  return nearest or (ranges[1] and ranges[1].candidate)
end
M._candidate_at_cursor = candidate_at_cursor

local function choose_variant(candidate, callback)
  local variants = candidate and candidate.variants or {}
  if #variants == 0 then callback(nil); return end
  if #variants == 1 then callback(variants[1]); return end
  vim.ui.select(variants, {
    prompt = 'Welke krantversie wil je bekijken?',
    format_item = function(variant)
      return (variant.publication or variant.edition or 'Onbekende krant')
        .. ' — ' .. (variant.display_date_label or 'datum onbekend')
    end,
  }, callback)
end

function M.show(result, callback, options)
  local report, ranges = M.report_lines(result, options)
  local width = math.min(100, math.max(54, vim.o.columns - 8))
  local height = math.min(math.max(16, #report), math.max(16, vim.o.lines - 8))
  local buf = vim.api.nvim_create_buf(false, true)
  local state = { done = false, mode = 'report' }
  local win

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'Pubble doublurecontrole')

  local function set_lines(lines)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
  end

  local function finish(approved)
    if state.done then return end
    state.done = true
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    callback(approved)
  end

  local function render_report()
    state.mode = 'report'
    set_lines(report)
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { ranges[1] and ranges[1].first or 1, 0 })
    end
  end

  local function selected_candidate()
    if not win or not vim.api.nvim_win_is_valid(win) then return nil end
    return candidate_at_cursor(ranges, vim.api.nvim_win_get_cursor(win)[1])
  end

  local function show_variant_text(variant)
    if not variant then return end
    state.mode = 'text'
    local lines = {
      variant.headline or 'Zonder kop',
      '',
      ('Krant: %s'):format(variant.publication or variant.edition or 'onbekend'),
      ('Publicatiedatum: %s'):format(variant.display_date_label or 'datum onbekend'),
      ('Aangemaakt: %s door %s'):format(
        variant.created_date_label or 'aanmaakdatum onbekend',
        variant.created_by or 'maker onbekend'
      ),
      ('Pubble: %s'):format(variant.editor_url or 'link onbekend'),
      '',
    }
    vim.list_extend(lines, vim.split(variant.text or variant.lead or '', '\n', { plain = true }))
    table.insert(lines, '')
    table.insert(lines, 'q/Escape = terug naar het overzicht')
    set_lines(lines)
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_cursor(win, { 1, 0 }) end
  end

  local function inspect_text()
    local candidate = selected_candidate()
    if not candidate then return end
    if candidate.variants_differ == true then
      choose_variant(candidate, show_variant_text)
    else
      show_variant_text((candidate.variants or {})[1] or {
        headline = candidate.headline,
        text = candidate.text,
        lead = candidate.lead,
      })
    end
  end

  local function open_article()
    local candidate = selected_candidate()
    if not candidate then return end
    choose_variant(candidate, function(variant)
      if not variant or not variant.editor_url then return end
      local ok, _, err = pcall(vim.ui.open, variant.editor_url)
      if not ok or err then
        vim.notify('Pubble-link openen mislukt: ' .. tostring(err or _), vim.log.levels.WARN)
      end
    end)
  end

  win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = 'minimal',
    border = 'rounded',
    title = ' Pubble-controle ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  render_report()

  vim.keymap.set('n', 'o', open_article, { buffer = buf, silent = true, desc = 'Open in Pubble' })
  vim.keymap.set('n', 't', inspect_text, { buffer = buf, silent = true, desc = 'Toon volledige tekst' })
  vim.keymap.set('n', '<CR>', inspect_text, { buffer = buf, silent = true, desc = 'Toon volledige tekst' })
  vim.keymap.set('n', 'v', function() finish(true) end, {
    buffer = buf, silent = true, desc = (options or {}).approve_label or 'Toch verzenden',
  })
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      if state.mode == 'text' then render_report() else finish(false) end
    end, { buffer = buf, silent = true, desc = 'Terug of annuleren' })
  end
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if not state.done then finish(false) end
    end,
  })
end

function M.check(command, callback, options)
  options = options or {}
  notifications.workflow('Pubble wordt gecontroleerd op mogelijke doublures…', vim.log.levels.INFO)
  local function handle_result(result)
    vim.schedule(function()
      if options.is_current and not options.is_current() then
        callback(false, nil)
        return
      end
      local ok, data = pcall(vim.fn.json_decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(data) ~= 'table'
          or data.version ~= 1 or type(data.candidates) ~= 'table' then
        local detail = vim.trim(result.stderr or result.stdout or '')
        local continue_label = options.failure_continue_label or 'Toch verzenden'
        local prompt = 'Doublurecontrole mislukt'
          .. (detail ~= '' and (': ' .. trim_text(detail, 180)) or '')
          .. '. Wat wil je doen?'
        if options.automatic then
          -- Automatische importvragen gebruiken geen fzf-provider: die kan
          -- de eventloop tijdens het starten van de embedded TUI bezet houden.
          local choice = vim.fn.confirm(prompt, '&' .. continue_label .. '\n&Annuleren', 2)
          callback(choice == 1, nil)
          return
        end
        vim.ui.select({ continue_label, 'Annuleren' }, {
          prompt = prompt,
        }, function(choice)
          callback(choice == continue_label, nil)
        end)
        return
      end
      if #data.candidates == 0 then
        callback(true, data)
        return
      end
      M.show(data, function(approved)
        callback(approved, data)
      end, options)
    end)
  end
  local started, err = pcall(vim.system, command, { text = true }, handle_result)
  if not started then handle_result({ code = 1, stderr = tostring(err) }) end
end

return M
