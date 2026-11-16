-- Dunne NeoVim-client voor de read-only vaste-paginazoeker van De Brug.
-- Editie-, Pubble- en AI-logica blijven in texttools.newspaper_page_search.

local M = {}

local browser = require 'ordered_browser'
local commands = require 'texttools_commands'
local context_help = require 'context_help'
local notifications = require 'texttools_notify'

local python = commands.bin 'python'
local module = 'texttools.newspaper_page_search_cli'

local choices = {
  { code = 'all', label = 'Beide pagina’s' },
  { code = 'ondernemen', label = 'Ondernemen in Kampen' },
  { code = 'gemeentenieuws', label = 'Gemeentenieuws' },
}

local function command(preset)
  return { python, '-m', module, '--json', '--preset', preset or 'all' }
end

local function sanitize(value)
  return tostring(value or ''):gsub('[\r\n]+', ' ')
end

local function page_label(value)
  if type(value) == 'number' and value > 0 then return 'pagina ' .. tostring(value) end
  return 'nog niet geplaatst'
end

function M._render(result)
  local edition = result.edition or {}
  local lines = {
    string.format('Vaste-paginakandidaten · %s · %s',
      sanitize(edition.publication or 'De Brug'),
      tostring(edition.publication_date or '?'):sub(1, 10)),
    string.rep('=', 72),
    string.format('Editie-ID: %s · %d bericht(en) beoordeeld · %d AI-ronde(s)',
      tostring(edition.edition_id or '?'), result.assessed_article_count or 0,
      result.ai_call_count or 0),
    'Alleen-lezen voorstel: er is niets in Pubble gewijzigd.',
    '',
  }
  local ranges = {}
  local labels = result.preset_labels or {}
  for _, preset in ipairs(result.requested_presets or {}) do
    local candidates = (result.candidates or {})[preset] or {}
    table.insert(lines, string.format('%s (%d)', sanitize(labels[preset] or preset), #candidates))
    table.insert(lines, string.rep('-', 72))
    if #candidates == 0 then
      table.insert(lines, '  Geen kandidaten gevonden.')
    end
    for _, item in ipairs(candidates) do
      table.insert(lines, string.format('  [%s] %s — %s',
        sanitize(item.verdict), sanitize(item.headline), page_label(item.page_number)))
      ranges[#lines] = { candidate = item, preset = preset }
      table.insert(lines, '    ' .. sanitize(item.reason))
    end
    table.insert(lines, '')
  end
  local failures = result.detail_failures or {}
  if #failures > 0 then
    table.insert(lines, string.format(
      'Let op: van %d bericht(en) kon alleen de kop/zoekmetadata worden beoordeeld.', #failures))
    table.insert(lines, '')
  end
  table.insert(lines, 'Enter = details  •  o = openen in Pubble  •  q = sluiten')
  return lines, ranges
end

local function open_detail(item, preset_label)
  local body = {
    sanitize(item.headline) ~= '' and item.headline or 'Zonder kop',
    '',
    ('Pagina: %s'):format(page_label(item.page_number)),
    ('Paginapreset: %s'):format(sanitize(preset_label)),
    ('Beoordeling: %s'):format(sanitize(item.verdict)),
    ('Reden: %s'):format(sanitize(item.reason)),
    ('Aanwijzing uit artikel: %s'):format(sanitize(item.evidence)),
    ('Categorie: %s'):format(sanitize(item.category) ~= '' and sanitize(item.category) or '-'),
    ('Aantal woorden: %s'):format(tostring(item.word_count or 'onbekend')),
    ('Pubble-detail beschikbaar: %s'):format(item.detail_available == false and 'nee' or 'ja'),
    ('Pubble: %s'):format(tostring(item.editor_url or '')),
  }
  if sanitize(item.working_title) ~= '' then
    table.insert(body, 2, 'Werktitel: ' .. sanitize(item.working_title))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, 'Paginakandidaat: ' .. sanitize(item.headline))
  require('buffer_navigation').show(buf)
  vim.keymap.set('n', 'o', function()
    if item.editor_url then browser.open_urls { tostring(item.editor_url) } end
  end, { buffer = buf, silent = true, desc = 'Artikel in Pubble openen' })
  vim.keymap.set('n', 'q', function() require('buffer_navigation').back(buf) end,
    { buffer = buf, silent = true, desc = 'Terug' })
end

local function show_report(result)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines, ranges = M._render(result)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, 'Vaste-paginakandidaten')
  context_help.register(buf, {
    title = 'Vaste-paginakandidaten',
    status = 'AI-voorstellen uit uitsluitend de aanstaande De Brug-editie.',
    sections = {
      {
        heading = 'Beoordelen',
        lines = {
          'Enter  Toon reden, tekstaanwijzing en artikelgegevens.',
          'o      Open het artikel in Pubble.',
          'q      Sluit het overzicht.',
        },
      },
      {
        heading = 'Let op',
        lines = {
          'Sterk en mogelijk zijn voorstellen; de redacteur beslist.',
          'De zoekactie verplaatst, wijzigt of publiceert geen bericht.',
        },
      },
    },
  })
  require('buffer_navigation').show(buf)
  local win = vim.api.nvim_get_current_win()

  local function entry_at_cursor()
    return ranges[vim.api.nvim_win_get_cursor(win)[1]]
  end

  vim.keymap.set('n', '<CR>', function()
    local entry = entry_at_cursor()
    if not entry then
      notifications.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      return
    end
    local label = (result.preset_labels or {})[entry.preset] or entry.preset
    open_detail(entry.candidate, label)
  end, { buffer = buf, silent = true, desc = 'Paginakandidaat bekijken' })

  vim.keymap.set('n', 'o', function()
    local entry = entry_at_cursor()
    if not entry or not entry.candidate.editor_url then
      notifications.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      return
    end
    browser.open_urls { tostring(entry.candidate.editor_url) }
  end, { buffer = buf, silent = true, desc = 'Artikel in Pubble openen' })

  vim.keymap.set('n', 'q', function() require('buffer_navigation').back(buf) end,
    { buffer = buf, silent = true, desc = 'Overzicht sluiten' })
end

function M.run(preset)
  preset = preset or 'all'
  notifications.workflow('Aanstaande De Brug · vaste pagina’s zoeken…', vim.log.levels.INFO,
    { kind = 'progress' })
  notifications.system(command(preset), {
    text = true,
    texttools_activity = { action = 'Aanstaande krant · vaste pagina’s zoeken' },
  }, function(process)
    notifications.schedule(function()
      if process.code ~= 0 then
        notifications.notify(vim.trim(process.stderr or '') ~= '' and vim.trim(process.stderr)
          or 'Vaste-paginazoeker mislukt.', vim.log.levels.ERROR)
        return
      end
      local ok, result = pcall(vim.json.decode, vim.trim(process.stdout or ''),
        { luanil = { object = true, array = true } })
      if not ok or type(result) ~= 'table' then
        notifications.notify('Onleesbaar antwoord van de vaste-paginazoeker.', vim.log.levels.ERROR)
        return
      end
      show_report(result)
      notifications.workflow('Vaste-paginazoeker klaar: overzicht geopend.', vim.log.levels.INFO,
        { ttl = 8, kind = 'success' })
    end)
  end)
end

function M.menu()
  vim.ui.select(choices, {
    prompt = 'Welke vaste pagina wil je vullen?',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then M.run(choice.code) end
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('KrantPaginaZoek', function(opts)
    M.run(opts.args ~= '' and opts.args or 'all')
  end, {
    nargs = '?',
    complete = function() return { 'all', 'ondernemen', 'gemeentenieuws' } end,
    desc = 'Zoek kandidaten voor vaste pagina’s in de aanstaande De Brug-editie',
  })
  vim.keymap.set('n', '<leader>ks', M.menu, {
    desc = '[K]rant vaste pagina’s [s]cannen',
  })
end

M._command = command

return M
