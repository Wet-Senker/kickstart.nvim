local M = {}
local notifications = require('texttools_notify')
local context_help = require('context_help')
local workflow_log = require('workflow_log')
local browser = require('ordered_browser')

local function trim_text(value, maximum)
  local text = vim.trim(tostring(value or '')):gsub('%s+', ' ')
  if #text <= maximum then return text end
  return text:sub(1, maximum - 1):gsub('%s+$', '') .. '…'
end

-- nvim_buf_set_lines weigert regels met een ingebedde newline; koppen en
-- datumlabels uit Pubble bevatten die soms. Sla ze plat tot één regel.
local function flatten(value)
  if value == nil or value == vim.NIL then return '' end
  return (vim.trim(tostring(value or '')):gsub('%s+', ' '))
end

local function nonempty(...)
  for index = 1, select('#', ...) do
    local value = select(index, ...)
    if type(value) == 'string' and vim.trim(value) ~= '' then return value end
  end
end

local function display_date(value)
  local text = flatten(value)
  if text == '' then return 'datum onbekend' end
  local year, month, day, suffix = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$')
  if year then return day .. '-' .. month .. '-' .. year .. suffix end
  return text
end

local function publication_name(value)
  local name = flatten(value)
  -- Oude agenda-antwoorden geven alleen de code. Gebruik de bestaande
  -- gecachete canonieke tabel; geen tweede namenlijst in de client.
  if name:match('^[A-Z][A-Z]?$') then return require('editions').name(name) end
  return name ~= '' and name or 'Onbekende krant'
end

local function kind_label(candidate, variant, options)
  local kind = nonempty(variant and variant.kind, candidate.kind, options.kind) or 'web'
  return ({ agenda = 'Agenda', web = 'Web' })[kind] or 'Onbekend'
end

local function candidate_date(candidate, variant)
  variant = variant or {}
  return display_date(nonempty(variant.display_date_short, variant.display_date_label,
    candidate.display_date_short, candidate.display_date_label))
end

local function pad(value, width)
  return value .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(value)))
end

-- Breedte volgt de inhoud met een leesbare ondergrens, tot 110 kolommen en
-- nooit buiten het scherm. Lange koppen mogen ombreken; de eerste regel houdt
-- soort en datum uitgelijnd. Bij korte inhoud geen onnodig brede doos.
function M._dialog_width(report, columns)
  local longest = 0
  for _, line in ipairs(report or {}) do
    longest = math.max(longest, vim.fn.strdisplaywidth(line))
  end
  local screen_cap = math.min(110, math.max(1, (columns or 80) - 4))
  return math.min(screen_cap, math.max(64, longest + 2))
end

local function grouped_entries(candidates)
  local groups, order = {}, {}
  local function add(publication, candidate, variant)
    publication = publication or 'Onbekende krant'
    if not groups[publication] then
      groups[publication] = {}
      table.insert(order, publication)
    end
    table.insert(groups[publication], { candidate = candidate, variant = variant })
  end

  for _, candidate in ipairs(candidates or {}) do
    local seen = {}
    for _, variant in ipairs(candidate.variants or {}) do
      local publication = variant.publication or variant.edition or 'Onbekende krant'
      if not seen[publication] then
        add(publication, candidate, variant)
        seen[publication] = true
      end
    end
    if not next(seen) then
      for _, publication in ipairs(candidate.publications or {}) do
        if not seen[publication] then
          add(publication, candidate, nil)
          seen[publication] = true
        end
      end
    end
    if not next(seen) then add('Onbekende krant', candidate, nil) end
  end
  return groups, order
end
M._grouped_entries = grouped_entries

function M.report_lines(result, options)
  options = options or {}
  local candidates = type(result) == 'table' and result.candidates or {}
  local lines = {
    -- De titel staat al op de vensterrand; herhaal hem niet in de inhoud.
    #candidates == 1
        and 'Dit artikel lijkt op een bericht dat al in Pubble staat.'
      or ('Dit artikel lijkt op %d berichten die al in Pubble staan.'):format(#candidates),
    '',
  }
  if result.combined and #(result.errors or {}) > 0 then
    lines[1] = 'Controle niet volledig. Beoordeel de treffers; een ontbrekende controle is geen groen licht.'
    for _, message in ipairs(result.errors) do table.insert(lines, 'LET OP: ' .. flatten(message)) end
    table.insert(lines, '')
  end
  if result.agenda_decision == 'skip' then
    table.insert(lines, 'Agenda overgeslagen voor dit artikel. Beoordeel hieronder nog de webtreffers.')
    table.insert(lines, '')
  end
  -- Het nieuwe bericht is vergelijkingsmateriaal, niet nog een treffer. Toon
  -- het eenmaal bovenaan, ook als meerdere bestaande berichten erop lijken.
  local comparisons, seen_comparisons = {}, {}
  for _, candidate in ipairs(candidates) do
    local comparison = candidate.comparison
    if type(comparison) == 'table' then
      local key = flatten(comparison.headline) .. '\n' .. flatten(comparison.date)
      if not seen_comparisons[key] then
        seen_comparisons[key] = #comparisons + 1
        comparisons[#comparisons + 1] = comparison
      end
    end
  end
  if #comparisons > 0 then
    table.insert(lines, options.comparison_heading or 'Nieuw bericht ter vergelijking')
    for index, comparison in ipairs(comparisons) do
      local prefix = #comparisons > 1 and (index .. '. ') or ''
      table.insert(lines, '  ' .. pad(display_date(comparison.date), 15) .. '  '
        .. prefix .. flatten(comparison.headline or 'Zonder kop'))
    end
    table.insert(lines, '')
  end
  local ranges = {}
  local groups, order = grouped_entries(candidates)
  local date_width, kind_width = 15, 6
  for _, publication in ipairs(order) do
    for _, entry in ipairs(groups[publication]) do
      local variant, candidate = entry.variant or {}, entry.candidate
      date_width = math.max(date_width, vim.fn.strdisplaywidth(candidate_date(candidate, variant)))
      kind_width = math.max(kind_width, vim.fn.strdisplaywidth(kind_label(candidate, variant, options)))
    end
  end
  for _, publication in ipairs(order) do
    table.insert(lines, publication_name(publication))
    table.insert(lines, '  ' .. pad('Soort', kind_width) .. '  ' .. pad('Datum', date_width) .. '  Bestaand bericht')
    for _, entry in ipairs(groups[publication]) do
      local row = #lines + 1
      local headline = flatten(
        entry.variant and entry.variant.headline
          or entry.candidate.headline
          or 'Zonder kop'
      )
      local variant = entry.variant or {}
      local date = candidate_date(entry.candidate, variant)
      local author = flatten(
        nonempty(variant.created_by_label, variant.created_by, entry.candidate.created_by_label, entry.candidate.created_by)
      )
      local row_text = '  ' .. pad(kind_label(entry.candidate, entry.variant, options), kind_width)
        .. '  ' .. pad(date, date_width) .. '  ' .. headline
      if entry.candidate.reviewed then row_text = row_text .. '  ✓ Geen doublure' end
      if author ~= '' then row_text = row_text .. '  ·  ' .. author end
      table.insert(lines, row_text)
      ranges[#ranges + 1] = {
        first = row,
        last = row,
        candidate = entry.candidate,
        variant = entry.variant,
      }
      if #comparisons > 1 and type(entry.candidate.comparison) == 'table' then
        local comparison = entry.candidate.comparison
        local key = flatten(comparison.headline) .. '\n' .. flatten(comparison.date)
        table.insert(lines, '    Vergelijk met nieuw bericht ' .. seen_comparisons[key])
        ranges[#ranges].last = #lines
      elseif entry.candidate.comparison_label and not entry.candidate.comparison then
        table.insert(lines, '    ' .. flatten(entry.candidate.comparison_label))
        ranges[#ranges].last = #lines
      end
    end
    table.insert(lines, '')
  end
  local approve_label = options.approve_label or 'toch verzenden'
  table.insert(lines, 'Bekijken — dit neemt nog geen besluit')
  table.insert(lines, '  Enter / dubbelklik  Bekijk de beschikbare tekst en details in NVIM')
  table.insert(lines, '  o                   Open alleen het geselecteerde bestaande bericht in Pubble')
  table.insert(lines, '')
  table.insert(lines, 'Beslissen')
  table.insert(lines, '  m  Dit paar is geen doublure; andere treffers blijven staan')
  table.insert(lines, '  v  Deze waarschuwingen negeren en ' .. approve_label)
  if options.reject_label then table.insert(lines, '  n  ' .. options.reject_label) end
  table.insert(lines, '  q  ' .. (options.cancel_label or 'Controle afbreken; niets verzenden of aanmaken'))
  return lines, ranges
end

local function entry_at_cursor(ranges, row)
  for _, range in ipairs(ranges) do
    if row >= range.first and row <= range.last then return range end
  end
  return nil
end
M._entry_at_cursor = entry_at_cursor

local function candidate_at_cursor(ranges, row)
  local entry = entry_at_cursor(ranges, row)
  return entry and entry.candidate or nil
end
M._candidate_at_cursor = candidate_at_cursor

local function choose_variant(candidate, callback)
  local variants = candidate and candidate.variants or {}
  if #variants == 0 then callback(nil); return end
  if #variants == 1 then callback(variants[1]); return end
  vim.ui.select(variants, {
    prompt = 'Welke krantversie wil je bekijken?',
    format_item = function(variant)
      return publication_name(variant.publication or variant.edition)
        .. ' — ' .. candidate_date(candidate, variant)
    end,
  }, callback)
end

function M.show(result, callback, options)
  if result.review_version == 1 and options and options.selection_review then
    return require('duplicate_selection_ui').show(result, callback, options)
  end
  local report, ranges = M.report_lines(result, options)
  local width = M._dialog_width(report, vim.o.columns)
  local height = math.min(math.max(16, #report), math.max(16, vim.o.lines - 8))
  local buf = vim.api.nvim_create_buf(false, true)
  options = options or {}
  local state = { done = false, mode = 'report', back_line = nil }
  local win

  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  vim.api.nvim_buf_set_name(buf, 'Pubble doublurecontrole')
  context_help.register(buf, function()
    local approve_label = (options or {}).approve_label or 'toch verzenden'
    if state.mode == 'text' then
      return {
        title = 'Mogelijke doublure',
        status = 'Beschikbare tekst en details van één bestaand bericht; nog geen besluit genomen.',
        sections = {
          {
            heading = 'Nu doen',
            lines = { 'Vergelijk deze tekst met het nieuwe artikel.' },
          },
          {
            heading = 'Andere hoofdopties',
            lines = {
              'o  Open deze bestaande versie in Pubble.',
              'm  Markeer alleen deze kandidaat als geen doublure.',
              'q  Terug naar het overzicht zonder een besluit te nemen.',
              'v  Getoonde doublures negeren en ' .. approve_label .. '.',
            },
          },
        },
      }
    end
    return {
      title = options.title or 'Mogelijke doublures',
      status = string.format('%d bestaand(e) bericht(en) vragen om een bewuste beoordeling.', #(result.candidates or {})),
      sections = {
        {
          heading = 'Eerst beoordelen',
          lines = {
            'Enter of t  Bekijk beschikbare tekst/details in NVIM; dit beslist niets.',
            'o           Open de geselecteerde versie in Pubble.',
            'm           Geen doublure: beoordeel alleen deze kandidaat.',
          },
        },
        {
          heading = 'Beslissen',
          lines = {
            'v  Getoonde doublures negeren en ' .. approve_label .. '.',
            'q  ' .. (options.cancel_label or 'Annuleren; de getoonde doublures kunnen later terugkomen.'),
            options.reject_label and ('n  ' .. options.reject_label) or 'm  Alleen deze kandidaat als geen doublure beoordelen.',
          },
        },
      },
    }
  end)

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
    report, ranges = M.report_lines(result, options)
    set_lines(report)
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, { ranges[1] and ranges[1].first or 1, 0 })
    end
  end

  local function selected_candidate()
    if not win or not vim.api.nvim_win_is_valid(win) then return nil, nil end
    if state.mode == 'text' then return state.candidate, state.variant end
    local entry = entry_at_cursor(ranges, vim.api.nvim_win_get_cursor(win)[1])
    return entry and entry.candidate or nil, entry and entry.variant or nil
  end

  local function reject_agenda()
    if not result.combined then finish('reject'); return end
    if options.is_current and not options.is_current() then finish(false); return end
    result.agenda_decision = 'skip'
    if options.reject_finishes_review then
      -- Vroeg n is één bewerkingskeuze, géén akkoord om web te publiceren.
      result.editing_only = true
      finish(true)
      return
    end
    options.reject_label = nil
    -- Een expliciet overgeslagen agenda hoeft ook niet meer op haar
    -- uitleesfout beoordeeld te worden. Webfouten blijven wel zichtbaar.
    if result.checks and result.checks.web then
      result.errors = {}
      for _, message in ipairs(result.checks.web.errors or {}) do
        result.errors[#result.errors + 1] = 'web: ' .. message
      end
    end
    local remaining = {}
    for _, candidate in ipairs(result.candidates or {}) do
      if candidate.kind ~= 'agenda' then remaining[#remaining + 1] = candidate end
    end
    result.candidates = remaining
    for _, candidate in ipairs(remaining) do
      if not candidate.reviewed then render_report(); return end
    end
    if #(result.errors or {}) > 0 then render_report(); return end
    finish(true)
  end

  local function show_variant_text(variant, candidate)
    if state.done or not vim.api.nvim_buf_is_valid(buf) then return end
    if not variant and not candidate then return end
    state.mode = 'text'
    state.candidate, state.variant = candidate, variant
    variant = variant or candidate
    local lines = {
      variant.headline or candidate.headline or 'Zonder kop',
      '',
      ('Soort: %s'):format(kind_label(candidate, variant, options)),
      ('Krant: %s'):format(publication_name(variant.publication or variant.edition)),
      ('Datum: %s'):format(candidate_date(candidate, variant)),
      ('Pubble: %s'):format(variant.editor_url or 'link onbekend'),
      '',
    }
    local created_date = nonempty(variant.created_date_short, variant.created_date_label)
    local author = nonempty(variant.created_by_label, variant.created_by)
    if created_date or author then
      table.insert(lines, 7, ('Aangemaakt: %s door %s'):format(
        display_date(created_date), author or 'maker onbekend'))
    end
    if nonempty(variant.location) then table.insert(lines, 'Locatie: ' .. flatten(variant.location)) end
    if nonempty(variant.city) then table.insert(lines, 'Plaats: ' .. flatten(variant.city)) end
    local text = nonempty(variant.text, variant.lead, candidate.text, candidate.lead) or ''
    if vim.trim(text) == '' then
      table.insert(lines, 'Geen berichttekst meegeleverd. Gebruik o om het bestaande bericht in Pubble te bekijken.')
    else
      vim.list_extend(lines, vim.split(text, '\n', { plain = true }))
    end
    table.insert(lines, '')
    table.insert(lines, '← Terug naar overzicht (Enter of q)')
    state.back_line = #lines
    set_lines(lines)
    if win and vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_cursor(win, { 1, 0 }) end
  end

  local function inspect_text()
    local candidate, selected_variant = selected_candidate()
    if not candidate then return end
    if selected_variant then
      show_variant_text(selected_variant, candidate)
    elseif candidate.variants_differ == true then
      choose_variant(candidate, function(variant) show_variant_text(variant, candidate) end)
    else
      show_variant_text((candidate.variants or {})[1], candidate)
    end
  end

  local function open_article()
    local candidate, selected_variant = selected_candidate()
    if not candidate then return end
    if selected_variant and selected_variant.editor_url then
      browser.open_urls { selected_variant.editor_url }
      return
    end
    choose_variant(candidate, function(variant)
      if not variant or not variant.editor_url then return end
      browser.open_urls { variant.editor_url }
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
    title = ' ' .. (options.title or 'Mogelijke doublures') .. ' ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = true
  vim.wo[win].winblend = 0
  vim.wo[win].winhighlight = 'Normal:Normal,FloatBorder:FloatBorder'
  vim.wo[win].linebreak = true
  render_report()

  vim.keymap.set('n', 'o', open_article, { buffer = buf, silent = true, desc = 'Open in Pubble' })
  vim.keymap.set('n', 'm', function()
    local candidate = selected_candidate()
    if not candidate or candidate.reviewed or state.marking then return end
    if options.is_current and not options.is_current() then
      notifications.notify('Artikel gewijzigd; controleer opnieuw voordat je een kandidaat beoordeelt.', vim.log.levels.WARN)
      finish(false)
      return
    end
    local function marked(ok)
      state.marking = false
      if not ok or state.done or not vim.api.nvim_buf_is_valid(buf) then return end
      if options.is_current and not options.is_current() then finish(false); return end
      candidate.reviewed = true
      for _, item in ipairs(result.candidates or {}) do
        if not item.reviewed then render_report(); return end
      end
      if result.combined and #(result.errors or {}) > 0 then render_report(); return end
      finish(true)
    end
    state.marking = true
    if options.on_mark then options.on_mark(candidate, marked) else marked(true) end
  end, { buffer = buf, silent = true, desc = 'Alleen deze kandidaat is geen doublure' })
  vim.keymap.set('n', 't', inspect_text, { buffer = buf, silent = true, desc = 'Toon volledige tekst' })
  vim.keymap.set('n', '<CR>', function()
    if state.mode == 'text' then
      if vim.api.nvim_win_get_cursor(win)[1] == state.back_line then render_report() end
      return
    end
    inspect_text()
  end, { buffer = buf, silent = true, desc = 'Open tekst of ga terug' })
  vim.keymap.set('n', '<2-LeftMouse>', function()
    local mouse = vim.fn.getmousepos()
    if mouse.winid ~= win or not mouse.line then return end
    vim.api.nvim_win_set_cursor(win, { mouse.line, math.max(0, (mouse.column or 1) - 1) })
    if state.mode == 'text' then
      if mouse.line == state.back_line then render_report() end
    else
      inspect_text()
    end
  end, { buffer = buf, silent = true, desc = 'Open doublure of ga terug' })
  vim.keymap.set('n', 'v', function() finish(true) end, {
    buffer = buf, silent = true, desc = (options or {}).approve_label or 'Toch verzenden',
  })
  if options.reject_label then
    vim.keymap.set('n', 'n', reject_agenda,
      { buffer = buf, desc = options.reject_label })
  end
  -- Bewust géén <Esc> als sluit-/annuleertoets: Escape is spiergeheugen om uit
  -- insert-mode te gaan; als dit dialoog tijdens het typen verschijnt zou een
  -- reflexmatige Escape de controle anders per ongeluk annuleren. Sluiten/terug
  -- gaat met q.
  vim.keymap.set('n', 'q', function()
    if state.mode == 'text' then render_report() else finish(false) end
  end, { buffer = buf, silent = true, desc = 'Terug of annuleren' })
  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    once = true,
    callback = function()
      if not state.done then finish(false) end
    end,
  })

  -- Bevestig de focus. nvim_open_win(enter=true) zet de focus meestal al, maar
  -- als dit dialoog tijdens een verse import/embedded TUI-sessie opent kan de
  -- focus in de onderliggende buffer blijven hangen (cursor 'erachter'). Zet
  -- het actieve venster daarom expliciet — nu en nog eens op de volgende tick.
  local function focus_dialog()
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_set_current_win, win)
    end
  end
  focus_dialog()
  notifications.schedule(focus_dialog)
end

function M.check(command, callback, options)
  options = options or {}
  local trace_buf = options.buf
  if type(trace_buf) ~= 'number' or not vim.api.nvim_buf_is_valid(trace_buf) then
    trace_buf = vim.api.nvim_get_current_buf()
  end
  local trace = workflow_log.start(trace_buf, 'Pubble · Doublurecontrole', {
    command = vim.fn.fnamemodify(tostring(command[1] or ''), ':t'),
  })
  local trace_finished = false
  local function finish_trace(outcome, detail)
    if trace_finished then return end
    trace_finished = true
    workflow_log.finish(trace, outcome, detail)
  end
  local function handle_result(result)
    notifications.schedule(function()
      if options.is_current and not options.is_current() then
        finish_trace('cancelled', { reason = 'stale_result', exit_code = result.code })
        callback(false, nil)
        return
      end
      local ok, data = pcall(vim.fn.json_decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(data) ~= 'table'
          or data.version ~= 1 or type(data.candidates) ~= 'table' then
        finish_trace('failed', {
          exit_code = result.code,
          error = result.code ~= 0 and 'ProcessExit' or 'InvalidResult',
        })
        local detail = vim.trim(result.stderr or result.stdout or '')
        notifications.workflow('Doublurecontrole mislukt. Controleer opnieuw vóór verzending.', vim.log.levels.ERROR, { buf = trace_buf })
        local continue_label = options.failure_continue_label or 'Toch verzenden'
        local prompt = 'Doublurecontrole mislukt'
          .. (detail ~= '' and (': ' .. trim_text(detail, 180)) or '')
          .. '. Wat wil je doen?'
        if options.automatic then
          -- Automatische importvragen gebruiken geen fzf-provider: die kan
          -- de eventloop tijdens het starten van de embedded TUI bezet houden.
          require('user_dialog').confirm_async(prompt, '&' .. continue_label .. '\n&Annuleren', 2, false, function(choice)
            callback(choice == 1 and vim.api.nvim_buf_is_valid(trace_buf)
              and (not options.is_current or options.is_current()), nil)
          end, { source_buf = trace_buf })
          return
        end
        vim.ui.select({ continue_label, 'Annuleren' }, {
          prompt = prompt,
        }, function(choice)
          callback(choice == continue_label, nil)
        end)
        return
      end
      finish_trace('succeeded', {
        exit_code = result.code,
        candidate_count = #data.candidates,
      })
      if data.performed == false then
        notifications.workflow('Doublurecontrole overgeslagen; er is niet op doublures gecontroleerd.', vim.log.levels.INFO, { buf = trace_buf })
      elseif data.history_complete == false then
        notifications.workflow('Doublurecontrole onvolledig; het resultaat is geen volledige controle.', vim.log.levels.WARN, { buf = trace_buf })
      elseif data.performed == true or data.history_complete == true then
        local message = #data.candidates == 0 and 'Doublurecontrole afgerond: geen mogelijke doublures gevonden.'
          or ('Doublurecontrole afgerond: %d mogelijke doublure(s) gevonden.'):format(#data.candidates)
        notifications.workflow(message, vim.log.levels.INFO, {
          buf = trace_buf, kind = #data.candidates == 0 and 'success' or nil, resolved = true,
          status = #data.candidates > 0 and 'Mogelijke doublures gevonden' or nil,
        })
      end
      if data.combined then
        local agenda = data.checks and data.checks.agenda
        local has_agenda = agenda and agenda.requested and not agenda.complete or false
        for _, candidate in ipairs(data.candidates) do if candidate.kind == 'agenda' then has_agenda = true end end
        if not has_agenda then options.reject_label = nil end
      end
      if #data.candidates == 0 and not (options.show_saved and #(data.saved_selections or {}) > 0)
          and not (data.combined and #(data.errors or {}) > 0) then
        callback(true, data)
        return
      end
      M.show(data, function(approved)
        callback(approved, data)
      end, options)
    end)
  end
  handle_result = notifications.bind(trace_buf, handle_result)
  local process_options = workflow_log.with_environment({ text = true }, trace)
  local started, err = pcall(notifications.system, command, process_options, handle_result)
  if not started then
    finish_trace('failed', { error = 'ProcessStartError' })
    handle_result({ code = 1, stderr = tostring(err) })
  end
end

return M
