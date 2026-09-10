-- Dunne NeoVim-client voor het agendabronregister (fase 1A/1B).
--
-- Deze module bevat geen eigen logica: hij roept exact dezelfde Python-acties en
-- JSON aan als de CLI (`texttools.agenda_cli`) en toont het resultaat in een apart
-- buffer. Zo blijft NeoVim een klant, geen programma. De papieren-agendafunctie
-- (`agenda_page.lua`, <leader>ka) blijft ongemoeid.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'

local python = commands.bin 'python'
local module = 'texttools.agenda_cli'
local BUFFER_NAME = 'Agendabronnen'

local editions = {
  { code = 'B', label = 'De Brug (B)' },
  { code = 'SW', label = 'De Swollenaer (SW)' },
  { code = 'ST', label = 'De Stadskoerier (ST)' },
  { code = 'D', label = 'De Drontenaar (D)' },
  { code = 'Z', label = 'Zeewolde Actueel (Z)' },
  { code = 'K', label = 'Nieuwsbode de Kop (K)' },
}

local status_order = { 'active', 'candidate', 'paused', 'rejected' }
local status_label = {
  active = 'ACTIEF',
  candidate = 'KANDIDAAT',
  paused = 'GEPAUZEERD',
  rejected = 'AFGEWEZEN',
}
local origin_label = { manual = 'handmatig', search = 'zoekronde' }

local function workflow(message, level, options) notifications.workflow(message, level, options) end

local function command(...)
  local result = { python, '-m', module, '--json' }
  for _, value in ipairs { ... } do
    table.insert(result, value)
  end
  return result
end

-- Zet de JSON-lijst met bronnen om in leesbare bufferregels. Pure functie, zodat
-- ze headless te testen is.
function M._render_lines(sources)
  local lines = { BUFFER_NAME, string.rep('=', #BUFFER_NAME), '' }
  if type(sources) ~= 'table' or #sources == 0 then
    table.insert(lines, 'Geen agendabronnen. Voeg er een toe met :AgendaBronToevoegen')
    return lines
  end

  local buckets = {}
  for _, status in ipairs(status_order) do buckets[status] = {} end
  for _, source in ipairs(sources) do
    local bucket = buckets[source.status] or buckets.candidate
    table.insert(bucket, source)
  end

  for _, status in ipairs(status_order) do
    local bucket = buckets[status]
    if #bucket > 0 then
      table.insert(lines, string.format('%s (%d)', status_label[status] or status, #bucket))
      for _, source in ipairs(bucket) do
        local name = (source.name ~= nil and source.name ~= '') and source.name or '(zonder naam)'
        local herkomst = origin_label[source.origin] or source.origin or '?'
        local plaatsen = (type(source.places) == 'table' and #source.places > 0)
            and table.concat(source.places, ', ')
          or '-'
        table.insert(
          lines,
          string.format('  [%s] %s — %s — editie %s — %s', tostring(source.id), name, herkomst, source.edition or '?', plaatsen)
        )
        table.insert(lines, '      ' .. (source.canonical_url or ''))
        if status == 'rejected' and source.reject_reason and source.reject_reason ~= '' then
          table.insert(lines, '      reden: ' .. source.reject_reason)
        end
        table.insert(lines, '      laatst gezien: ' .. (source.last_seen or '?'))
      end
      table.insert(lines, '')
    end
  end

  table.insert(lines, 'Toevoegen: :AgendaBronToevoegen  ·  Vernieuwen: :AgendaBronnen')
  return lines
end

local function find_overview_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name:sub(-#BUFFER_NAME) == BUFFER_NAME then return buf end
    end
  end
  return nil
end

local function show_overview(sources)
  local buf = find_overview_buffer()
  if not buf then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, BUFFER_NAME)
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].filetype = 'markdown'
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M._render_lines(sources))
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  -- Toon in een apart venster; overschrijf nooit de huidige (artikel)buffer.
  local win
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == buf then
      win = w
      break
    end
  end
  if win then
    vim.api.nvim_set_current_win(win)
  else
    vim.cmd 'botright vsplit'
    vim.api.nvim_win_set_buf(0, buf)
  end
end

-- Toon het overzicht van geregistreerde bronnen.
function M.overzicht()
  vim.system(command('bron', 'list'), { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(
          vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
            or 'Kon het bronoverzicht niet ophalen.',
          vim.log.levels.ERROR
        )
        return
      end
      local ok, decoded = pcall(vim.json.decode, vim.trim(result.stdout or ''))
      if not ok or type(decoded) ~= 'table' then
        vim.notify('Het bronoverzicht gaf geen leesbare JSON terug.', vim.log.levels.ERROR)
        return
      end
      show_overview(decoded)
    end)
  end)
end

local function run_add(url, edition, naam, plaatsen)
  local add = command('bron', 'add', url, '--editie', edition)
  if naam and naam ~= '' then
    table.insert(add, '--naam')
    table.insert(add, naam)
  end
  for _, plaats in ipairs(plaatsen or {}) do
    table.insert(add, '--plaats')
    table.insert(add, plaats)
  end

  vim.system(add, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(
          vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
            or 'Toevoegen van de bron is mislukt.',
          vim.log.levels.ERROR
        )
        return
      end
      local ok, decoded = pcall(vim.json.decode, vim.trim(result.stdout or ''))
      if not ok or type(decoded) ~= 'table' then
        vim.notify('De toevoegactie gaf geen leesbare JSON terug.', vim.log.levels.ERROR)
        return
      end
      local source = decoded.source or {}
      if decoded.created then
        workflow(string.format('Bron toegevoegd als kandidaat (id %s).', tostring(source.id)), vim.log.levels.INFO)
      elseif decoded.was_rejected then
        workflow('Deze bron bestond al en blijft afgewezen; niets overschreven.', vim.log.levels.WARN)
      else
        workflow(
          string.format('Bron bestond al (id %s, %s); last_seen bijgewerkt.', tostring(source.id), tostring(source.status)),
          vim.log.levels.INFO
        )
      end
      -- Ververs een reeds geopend overzicht, maar spring er niet ongevraagd heen.
      if find_overview_buffer() then M.overzicht() end
    end)
  end)
end

-- Handmatig een bron toevoegen via een korte reeks prompts.
function M.toevoegen()
  vim.ui.input({ prompt = 'Agendabron-URL: ' }, function(url)
    if not url or vim.trim(url) == '' then return end
    url = vim.trim(url)
    vim.ui.select(editions, {
      prompt = 'Voor welke editie?',
      format_item = function(item) return item.label end,
    }, function(edition)
      if not edition then return end
      vim.ui.input({ prompt = 'Naam (optioneel): ' }, function(naam)
        vim.ui.input({ prompt = 'Plaats(en), komma-gescheiden (optioneel): ' }, function(plaats_raw)
          local plaatsen = {}
          for _, part in ipairs(vim.split(plaats_raw or '', ',', { plain = true })) do
            local trimmed = vim.trim(part)
            if trimmed ~= '' then table.insert(plaatsen, trimmed) end
          end
          run_add(url, edition.code, naam and vim.trim(naam) or '', plaatsen)
        end)
      end)
    end)
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('AgendaBronnen', function() M.overzicht() end, {
    desc = 'Toon het overzicht van geregistreerde agendabronnen',
  })
  vim.api.nvim_create_user_command('AgendaBronToevoegen', function() M.toevoegen() end, {
    desc = 'Voeg handmatig een agendabron toe',
  })
  -- Geen eigen <leader>-mapping meer: de agenda-onlinemodule heeft één ingang,
  -- het menu op <leader>kg (dat bevat "Bronnen: overzicht/toevoegen" al). De
  -- commando's hierboven blijven als directe route beschikbaar.
end

M._command = command
M._editions = editions

return M
