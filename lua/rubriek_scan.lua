-- Dunne NeoVim-client voor de read-only rubriekscan van online webartikelen.
-- Toont artikelen die duidelijk onder een rubriek vallen maar niet in die
-- categorie staan. Wijzigt zelf niets in Pubble: openen doe je met o, corrigeren
-- (voorlopig) handmatig; m markeert een kandidaat als afgehandeld.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local context_help = require 'context_help'

local python = commands.bin 'python'
local module = 'texttools.rubriek_scan_cli'

local choices = {
  { code = 'all', label = 'Alle kranten (iedere site afzonderlijk)' },
  { code = 'B', label = 'De Brug' },
  { code = 'SW', label = 'De Swollenaer' },
  { code = 'ST', label = 'De Stadskoerier' },
  { code = 'D', label = 'De Drontenaar' },
  { code = 'Z', label = 'Zeewolde Actueel' },
  { code = 'K', label = 'Nieuwsbode de Kop' },
}

local function command(edition, include_reviewed)
  local result = { python, '-m', module, '--json', '--editie', edition or 'all' }
  if include_reviewed then table.insert(result, '--include-reviewed') end
  return result
end

local function mark_command()
  return { python, '-m', module, '--json', '--mark-reviewed' }
end

local function sanitize(value)
  return tostring(value or ''):gsub('[\r\n]+', ' ')
end

function M._render(result)
  local lines = {
    string.format('Rubriekvoorstellen webartikelen (%s..%s)', result.from or '?', result.to or '?'),
    string.rep('=', 68),
    '',
  }
  local ranges = {}
  for _, site in ipairs(result.sites or {}) do
    if site.error and site.error ~= vim.NIL then
      table.insert(lines, string.format('%s: NIET gelezen — %s',
        site.publication or site.edition, sanitize(site.error)))
    else
      local candidates = site.candidates or {}
      table.insert(lines, string.format('%s: %d artikel(en), %d voorstel(len)%s',
        site.publication or site.edition, site.article_count or 0, #candidates,
        #candidates > 0 and ':' or '.'))
      for _, item in ipairs(candidates) do
        local current = item.current_category_name
        if current == nil or current == vim.NIL then current = item.current_category_id end
        table.insert(lines, string.format('  %s%s (%s)  nu: %s → %s (score %s)',
          item.reviewed and '[afgehandeld] ' or '',
          sanitize(item.headline), item.display_date_label or '?',
          tostring(current == nil and 'onbekend' or current),
          sanitize(item.suggested_category_name or item.suggested_rubriek),
          tostring(item.score or '?')))
        ranges[#lines] = { candidate = item }
      end
      if (site.reviewed_hidden_count or 0) > 0 then
        table.insert(lines, string.format('  %d afgehandelde kandidaat(en) verborgen.',
          site.reviewed_hidden_count))
      end
    end
    table.insert(lines, '')
  end
  table.insert(lines,
    'Enter = details  •  o = in browser  •  m = afgehandeld  •  '
    .. 'r = afgehandelde tonen/verbergen  •  q = sluiten')
  return lines, ranges
end

local function mark_keys(keys, on_done)
  if not keys or #keys == 0 then
    vim.notify('Geen kandidaat om te markeren.', vim.log.levels.INFO)
    return
  end
  vim.system(mark_command(), { text = true, stdin = vim.json.encode { review_keys = keys } },
    function(process)
      vim.schedule(function()
        if process.code ~= 0 then
          vim.notify(vim.trim(process.stderr or '') ~= '' and vim.trim(process.stderr)
            or 'Markeren mislukt.', vim.log.levels.ERROR)
          return
        end
        notifications.workflow('Kandidaat gemarkeerd als afgehandeld.', vim.log.levels.INFO, { ttl = 8 })
        if on_done then on_done() end
      end)
    end)
end

-- Toon één kandidaat als losse, sluitbare buffer onder het overzicht.
local function open_detail_buffer(item)
  local current = item.current_category_name
  if current == nil or current == vim.NIL then current = item.current_category_id end
  local matched = item.matched
  if type(matched) == 'table' then matched = table.concat(matched, ', ') else matched = '' end
  local body = {
    sanitize(item.headline) ~= '' and item.headline or 'Zonder kop', '',
    ('Huidige categorie: %s'):format(tostring(current == nil and 'onbekend' or current)),
    ('Voorstel: %s (score %s)'):format(
      sanitize(item.suggested_category_name or item.suggested_rubriek), tostring(item.score or '?')),
    ('Gevonden woorden: %s'):format(matched),
    ('Pubble: %s'):format(tostring(item.editor_url or '')),
    '',
  }
  for _, line in ipairs(vim.split(item.lead or '', '\n', { plain = true })) do
    table.insert(body, line)
  end

  local abuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(abuf, 0, -1, false, body)
  vim.bo[abuf].filetype = 'markdown'
  vim.bo[abuf].modifiable = false
  vim.bo[abuf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, abuf, 'Rubriekvoorstel: ' .. sanitize(item.headline))
  vim.cmd 'belowright split'
  vim.api.nvim_win_set_buf(0, abuf)
  vim.api.nvim_win_set_height(0, math.max(8, math.min(20, #body)))
  -- Alleen q sluit; geen <Esc> (die is spiergeheugen voor insert-mode verlaten).
  for _, key in ipairs({ 'q' }) do
    vim.keymap.set('n', key, '<cmd>close<cr>', { buffer = abuf, silent = true, desc = 'Sluiten' })
  end
end

local function show_report(result, edition, include_reviewed)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines, ranges = M._render(result)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, 'Rubriekvoorstellen')
  context_help.register(buf, {
    title = 'Rubriekvoorstellen',
    status = 'Read-only voorstellen; de scan corrigeert zelf geen categorie in Pubble.',
    sections = {
      {
        heading = 'Beoordelen',
        lines = {
          'Enter  Bekijk de aanwijzingen en artikeltekst.',
          'o      Open het artikel in Pubble voor een handmatige correctie.',
        },
      },
      {
        heading = 'Afronden',
        lines = {
          'm  Markeer het voorstel als afgehandeld.',
          'r  Toon of verberg eerder afgehandelde voorstellen.',
          'q  Sluit het overzicht.',
        },
      },
      {
        heading = 'Let op',
        lines = { 'Afhandelen verbergt het voorstel in volgende scans; het wijzigt geen Pubble-categorie.' },
      },
    },
  })
  vim.cmd 'botright split'
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, math.max(10, math.min(#lines + 1, math.floor(vim.o.lines / 2))))

  local function entry_at_cursor()
    return ranges[vim.api.nvim_win_get_cursor(win)[1]]
  end

  local function redraw()
    lines, ranges = M._render(result)
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
  end

  vim.keymap.set('n', 'o', function()
    local entry = entry_at_cursor()
    if not entry or not entry.candidate.editor_url then
      vim.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      return
    end
    local ok, _, err = pcall(vim.ui.open, tostring(entry.candidate.editor_url))
    if not ok or err then
      vim.notify('Openen in browser mislukt: ' .. tostring(err or _), vim.log.levels.WARN)
    end
  end, { buffer = buf, silent = true, desc = 'Artikel in browser openen' })

  vim.keymap.set('n', '<CR>', function()
    local entry = entry_at_cursor()
    if not entry then
      vim.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      return
    end
    open_detail_buffer(entry.candidate)
  end, { buffer = buf, silent = true, desc = 'Details tonen' })

  vim.keymap.set('n', 'm', function()
    local entry = entry_at_cursor()
    if not entry or not entry.candidate.review_key then
      vim.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      return
    end
    mark_keys({ entry.candidate.review_key }, function()
      entry.candidate.reviewed = true
      redraw()
    end)
  end, { buffer = buf, silent = true, desc = 'Kandidaat als afgehandeld markeren' })

  vim.keymap.set('n', 'r', function()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    M.run(edition, { include_reviewed = not include_reviewed })
  end, { buffer = buf, silent = true, desc = 'Afgehandelde tonen/verbergen' })

  -- Alleen q sluit; geen <Esc> (die is spiergeheugen voor insert-mode verlaten).
  for _, key in ipairs({ 'q' }) do
    vim.keymap.set('n', key, function()
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end, { buffer = buf, silent = true, desc = 'Overzicht sluiten' })
  end
end

function M.run(edition, options)
  edition = edition or 'all'
  options = options or {}
  notifications.workflow('Webartikelen · rubrieken scannen…', vim.log.levels.INFO)
  vim.system(command(edition, options.include_reviewed), { text = true }, function(process)
    vim.schedule(function()
      if process.code ~= 0 then
        vim.notify(vim.trim(process.stderr or '') ~= '' and vim.trim(process.stderr)
          or 'Rubriekscan mislukt.', vim.log.levels.ERROR)
        return
      end
      local ok, result = pcall(vim.json.decode, vim.trim(process.stdout or ''),
        { luanil = { object = true, array = true } })
      if not ok or type(result) ~= 'table' then
        vim.notify('Onleesbare JSON van de rubriekscan.', vim.log.levels.ERROR)
        return
      end
      show_report(result, edition, options.include_reviewed == true)
      notifications.workflow('Rubriekscan klaar: overzicht geopend.', vim.log.levels.INFO, { ttl = 8 })
    end)
  end)
end

function M.menu()
  vim.ui.select(choices, {
    prompt = 'Welke krant(en) op rubriek scannen?',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then M.run(choice.code) end
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('RubriekScan', function(opts)
    M.run(opts.args ~= '' and opts.args or 'all')
  end, {
    nargs = '?',
    complete = function() return { 'all', 'B', 'SW', 'ST', 'D', 'Z', 'K' } end,
    desc = 'Scan actieve webartikelen op een waarschijnlijke rubriek (read-only)',
  })
  vim.keymap.set('n', '<leader>kr', M.menu, {
    desc = '[K]rant [r]ubriekscan (per site)',
  })
end

M._command = command
M._mark_command = mark_command

return M
