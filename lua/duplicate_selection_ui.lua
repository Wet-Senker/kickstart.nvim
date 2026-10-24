-- Presentation only. Python validates and persists every publication exclusion.
local M = {}
local notices = require 'texttools_notify'

local function flat(value) return tostring(value or ''):gsub('%s+', ' ') end
local function date(value)
  local text = flat(value)
  local year, month, day, rest = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$')
  return year and (day .. '-' .. month .. '-' .. year .. rest) or text
end

function M.show(report, callback, options)
  options = options or {}
  local entries, choices = {}, {}
  for _, candidate in ipairs(report.candidates or {}) do
    for _, variant in ipairs(candidate.variants or {}) do
      entries[#entries + 1] = { candidate = candidate, variant = variant,
        target = variant.review_target, selectable = variant.review_selectable }
    end
  end
  for _, saved in ipairs(report.saved_selections or {}) do
    choices[saved.id] = 'duplicate'
    entries[#entries + 1] = { target = saved, selectable = true, variant = {
      edition = saved.edition, headline = saved.headline, editor_url = saved.url,
      kind = saved.kind, text = (saved.existing or {}).text,
      display_date_short = (saved.existing or {}).display_date_short,
    }, candidate = { kind = saved.kind } }
  end
  table.sort(entries, function(a, b)
    local av, bv = a.variant, b.variant
    return flat(av.publication or av.edition) .. flat(av.headline)
      < flat(bv.publication or bv.edition) .. flat(bv.headline)
  end)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'Pubble doublurecontrole')
  local win, rows, done, detail, applying = nil, {}, false, nil, false
  local function finish(ok)
    if done then return end
    done = true
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
    callback(ok)
  end
  local function selected()
    return detail or rows[vim.api.nvim_win_get_cursor(win)[1]]
  end
  local function render()
    rows = {}
    local lines = {}
    if detail then
      local v = detail.variant
      lines = { flat(v.headline), '',
        'Krant: ' .. flat(v.publication or v.edition),
        'Publicatie: ' .. date(v.display_date_short or v.display_date_label),
        'Aangemaakt: ' .. date(v.created_date_short or v.created_date_label)
          .. ' door ' .. flat(v.created_by or 'maker onbekend'),
        'Pubble: ' .. flat(v.editor_url), '',
        flat(v.location), flat(v.city), '' }
      vim.list_extend(lines, vim.split(v.text or v.lead or 'Geen tekst beschikbaar; gebruik o voor Pubble.', '\n', { plain = true }))
      vim.list_extend(lines, { '', 'Enter / q  Terug naar het overzicht; nog geen keuzes toepassen.' })
    else
      lines = { 'Beoordeel per krant en per bestaand bericht.',
        '[ ] Onbeoordeeld   [=] Wel doublure: dit onderdeel overslaan   [≠] Geen doublure', '' }
      for _, message in ipairs(report.errors or {}) do lines[#lines + 1] = 'LET OP: ' .. flat(message) end
      local previous
      for _, entry in ipairs(entries) do
        local v = entry.variant
        local publication = v.publication or require('editions').name(v.edition) or v.edition or 'Onbekende krant'
        if publication ~= previous then lines[#lines + 1] = ''; lines[#lines + 1] = publication; previous = publication end
        local choice = entry.target and choices[entry.target.id]
        local marker = choice == 'duplicate' and '[=]' or choice == 'different' and '[≠]' or '[ ]'
        local kind = (v.kind or entry.candidate.kind) == 'agenda' and 'Agenda' or 'Web'
        lines[#lines + 1] = marker .. ' ' .. kind .. '  '
          .. date(v.display_date_short or v.display_date_label) .. '  ' .. flat(v.headline)
          .. (v.created_by and (' · ' .. flat(v.created_by)) or '')
          .. (entry.selectable and '' or '  (alleen bekijken: geen gekozen doelkrant)')
        rows[#lines] = entry
        local comparison = entry.candidate.comparison
        if comparison then
          lines[#lines + 1] = '    Nieuw: ' .. flat(comparison.date) .. '  ' .. flat(comparison.headline)
          rows[#lines] = entry
        end
      end
      vim.list_extend(lines, { '', 'Bekijken: Enter / dubbelklik = tekst; o = bestaand bericht in Pubble',
        'm  Wel doublure       n  Geen doublure       dezelfde toets nogmaals = wissen',
        'q  Keuzes toepassen en verder bewerken (niets publiceren)',
        'Ctrl-c  Uitstellen zonder wijzigingen; automatische agenda wacht',
        '', 'Zonder markering wordt niets als doublure bevestigd. Krantplaatsing blijft mogelijk.' })
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end
  local function toggle(value)
    if applying then return end
    local entry = selected()
    if not entry or not entry.target or not entry.selectable then return end
    local id = entry.target.id
    choices[id] = choices[id] ~= value and value or nil
    local cursor = vim.api.nvim_win_get_cursor(win)
    render()
    vim.api.nvim_win_set_cursor(win, cursor)
  end
  local function apply()
    if detail then detail = nil; render(); return end
    if applying then return end
    if options.is_current and not options.is_current() then finish(false); return end
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
  win = vim.api.nvim_open_win(buf, true, { relative = 'editor',
    width = math.min(110, math.max(20, vim.o.columns - 4)),
    height = math.min(math.max(16, #entries * 3 + 11), math.max(8, vim.o.lines - 6)),
    row = 2, col = 1, style = 'minimal', border = 'rounded', title = ' Mogelijke doublures ', title_pos = 'center' })
  vim.wo[win].wrap, vim.wo[win].linebreak = true, true
  render()
  for row = 1, vim.api.nvim_buf_line_count(buf) do
    if rows[row] then vim.api.nvim_win_set_cursor(win, { row, 0 }); break end
  end
  vim.keymap.set('n', 'm', function() toggle('duplicate') end, { buffer = buf })
  vim.keymap.set('n', 'n', function() toggle('different') end, { buffer = buf })
  vim.keymap.set('n', 'q', apply, { buffer = buf })
  vim.keymap.set('n', '<C-c>', function() if not applying then finish(false) end end, { buffer = buf })
  local function inspect()
    if detail then detail = nil else detail = selected() end
    render()
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
  end
  vim.keymap.set('n', '<CR>', inspect, { buffer = buf })
  vim.keymap.set('n', '<2-LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid == win and mouse.line then
      vim.api.nvim_win_set_cursor(win, { mouse.line, math.max(0, (mouse.column or 1) - 1) })
      inspect()
    end
  end, { buffer = buf })
  vim.keymap.set('n', 'o', function()
    local entry = selected()
    if entry and entry.variant.editor_url then require('ordered_browser').open_urls { entry.variant.editor_url } end
  end, { buffer = buf })
  require('context_help').register(buf, function() return {
    title = 'Doublurekeuzes', status = 'Keuzes worden pas met q toegepast; dit publiceert niets.',
    sections = { { heading = 'Bediening', lines = {
      'm: wel doublure; n: geen doublure; dezelfde toets wist de keuze.',
      'Een bevestiging geldt alleen voor deze krant en Web of dit afzonderlijke agenda-item.',
      'Enter: tekst bekijken/terug. o: bestaand bericht openen.',
      'q: opslaan en verder bewerken. Daarna bewust <leader>aw voor verzending.',
      'Ctrl-c: uitstellen zonder keuzes op te slaan; automatische agenda wacht.',
      'Een verwijderde meldingsregel wist geen opgeslagen doublurekeuze; heropen de controle.',
    } } },
  } end)
  vim.api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function() if not done then finish(false) end end })
end

return M
