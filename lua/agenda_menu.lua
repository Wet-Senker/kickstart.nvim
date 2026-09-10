-- Eén leader-menu voor de agenda-importmodule.
--
-- Bereikt alle acties via dezelfde Python-CLI/JSON als de terminal
-- (texttools.agenda_cli): bronnenoverzicht en -toevoegen (via agenda_bron),
-- een geplakt ## Kalender-document ontdubbelen tegen de eigen agenda (met of
-- zonder AI-normalisatie), en de eigen agenda per site op interne doublures
-- controleren. Verwijderen doet de redacteur zelf in Pubble; dit menu opent
-- hoogstens de bewerkpagina's.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'

local python = commands.bin 'python'
local module = 'texttools.agenda_cli'

local editions = {
  { code = 'B', label = 'De Brug (B)' },
  { code = 'SW', label = 'De Swollenaer (SW)' },
  { code = 'ST', label = 'De Stadskoerier (ST)' },
  { code = 'D', label = 'De Drontenaar (D)' },
  { code = 'Z', label = 'Zeewolde Actueel (Z)' },
  { code = 'K', label = 'Nieuwsbode de Kop (K)' },
}

local function workflow(message, level, options) notifications.workflow(message, level, options) end

local function command(...)
  local result = { python, '-m', module, '--json' }
  for _, value in ipairs { ... } do
    table.insert(result, value)
  end
  return result
end

-- nvim_buf_set_lines weigert regels met een newline erin; brontitels/teksten uit
-- Pubble bevatten die soms. Sla elke ingebedde newline plat tot een spatie.
local function sanitize_lines(lines)
  local safe = {}
  for _, line in ipairs(lines) do
    table.insert(safe, (tostring(line):gsub('[\r\n]', ' ')))
  end
  return safe
end

local function open_scratch(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, sanitize_lines(lines))
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.cmd 'botright vsplit'
  vim.api.nvim_win_set_buf(0, buf)
end

-- Pure renderers (headless testbaar).

function M._render_import(decoded)
  local lines = { 'Agenda-import', '=============', '' }
  table.insert(lines, 'Controle:')
  for _, v in ipairs(decoded.validation or {}) do
    if v.ok then
      table.insert(lines, string.format('  ✓ [%s] %s', v.ref, v.title))
    else
      local details = {}
      if v.missing and #v.missing > 0 then table.insert(details, 'ontbreekt: ' .. table.concat(v.missing, ', ')) end
      if v.problems and #v.problems > 0 then table.insert(details, 'probleem: ' .. table.concat(v.problems, '; ')) end
      table.insert(lines, string.format('  ✗ [%s] %s — %s', v.ref, v.title, table.concat(details, ' | ')))
    end
  end
  if decoded.read_incomplete then
    table.insert(lines, '')
    table.insert(lines, 'Let op: eigen agenda niet gelezen — onderstaande NIET bevestigd als nieuw.')
  end
  local candidates = decoded.candidates or {}
  table.insert(lines, '')
  table.insert(lines, string.format('Mogelijke doublures (%d):', #candidates))
  for _, c in ipairs(candidates) do
    table.insert(lines, string.format('  [%s] %s (%s) ↔ %s — %s (%d%%)',
      c.left.ref, c.left.title, c.left.date or '?', c.right.title, c.reason, c.score or 0))
  end
  local clean = decoded.clean or {}
  table.insert(lines, '')
  table.insert(lines, string.format('%s (%d):',
    decoded.read_incomplete and 'Nog te controleren' or 'Nieuw (geen doublure)', #clean))
  for _, e in ipairs(clean) do
    table.insert(lines, string.format('  [%s] %s (%s)', e.ref, e.title, e.date or '?'))
  end
  local normalized = decoded.normalized or {}
  if #normalized > 0 then
    table.insert(lines, '')
    table.insert(lines, 'Genormaliseerde teksten (AI-voorstel, brontekst blijft bewaard):')
    for _, n in ipairs(normalized) do
      if n.error and n.error ~= vim.NIL then
        table.insert(lines, string.format('  [%s] %s — AI-fout: %s', n.ref, n.title, n.error))
      else
        table.insert(lines, string.format('  [%s] %s:', n.ref, n.title))
        table.insert(lines, '      ' .. tostring(n.normalized))
      end
    end
  end
  return lines
end

function M._render_pairs(decoded)
  local paren = decoded.paren or {}
  local lines = {
    string.format('Eigen doublures — editie %s (%s..%s)', decoded.editie or '?', decoded.van or '?', decoded.tot or '?'),
    string.rep('=', 40), '',
    string.format('%d agenda-item(s) gelezen, %d mogelijk(e) doublure(s):', decoded.aantal_items or 0, #paren),
    '',
  }
  for _, p in ipairs(paren) do
    table.insert(lines, string.format('  %s (%s) ↔ %s — %s (%d%%)',
      p.left.title, p.left.date or '?', p.right.title, p.reason, p.score or 0))
    table.insert(lines, '      ' .. tostring(p.left.editor_url))
    table.insert(lines, '      ' .. tostring(p.right.editor_url))
  end
  if #paren == 0 then
    table.insert(lines, '  (geen)')
  end
  return lines
end

local function run(cmd, stdin, on_json)
  vim.system(cmd, { text = true, stdin = stdin }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
          or 'Agenda-actie mislukt.', vim.log.levels.ERROR)
        return
      end
      local ok, decoded = pcall(vim.json.decode, vim.trim(result.stdout or ''))
      if not ok or type(decoded) ~= 'table' then
        vim.notify('Onleesbare JSON van de agenda-actie.', vim.log.levels.ERROR)
        return
      end
      on_json(decoded)
    end)
  end)
end

local function pick_edition(callback)
  vim.ui.select(editions, {
    prompt = 'Voor welke editie?',
    format_item = function(item) return item.label end,
  }, function(edition)
    if edition then callback(edition.code) end
  end)
end

-- Acties.

function M.import_check(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  if vim.trim(text) == '' then
    vim.notify('De huidige buffer is leeg.', vim.log.levels.ERROR)
    return
  end
  local cmd = opts.normaliseer
      and command('import', '--editie', opts.editie or 'B', '--normaliseer')
    or command('import', '--editie', opts.editie or 'B')
  workflow('Agenda · import controleren…', vim.log.levels.INFO)
  run(cmd, text, function(decoded)
    open_scratch('Agenda-import', M._render_import(decoded))
  end)
end

function M.eigen_doublures(editie)
  workflow('Agenda · eigen doublures zoeken…', vim.log.levels.INFO)
  run(command('eigen-doublures', '--editie', editie or 'B'), nil, function(decoded)
    open_scratch('Eigen doublures', M._render_pairs(decoded))
    local urls = {}
    for _, p in ipairs(decoded.paren or {}) do
      for _, side in ipairs { p.left, p.right } do
        if side.editor_url and not vim.tbl_contains(urls, side.editor_url) then
          table.insert(urls, side.editor_url)
        end
      end
    end
    for _, url in ipairs(urls) do pcall(vim.ui.open, url) end
    if #urls > 0 then
      workflow(#urls .. ' item(s) in de browser geopend; bekijk en verwijder zelf in Pubble.',
        vim.log.levels.INFO, { ttl = 10 })
    end
  end)
end

function M.menu()
  local bron = require 'agenda_bron'
  local items = {
    { label = 'Bronnen: overzicht', fn = function() bron.overzicht() end },
    { label = 'Bronnen: toevoegen', fn = function() bron.toevoegen() end },
    { label = 'Import: ontdubbelen (huidige buffer)', fn = function()
      pick_edition(function(e) M.import_check { editie = e } end)
    end },
    { label = 'Import: ontdubbelen + AI-normaliseren', fn = function()
      pick_edition(function(e) M.import_check { editie = e, normaliseer = true } end)
    end },
    { label = 'Eigen agenda: doublures zoeken (per site)', fn = function()
      pick_edition(function(e) M.eigen_doublures(e) end)
    end },
  }
  vim.ui.select(items, {
    prompt = 'Agenda',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then choice.fn() end
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('Agenda', function() M.menu() end, {
    desc = 'Agenda-importmenu (bronnen, import, eigen doublures)',
  })
  vim.keymap.set('n', '<leader>kg', M.menu, {
    desc = '[K]rant a[g]enda-menu',
  })
end

M._command = command
M._sanitize_lines = sanitize_lines

return M
