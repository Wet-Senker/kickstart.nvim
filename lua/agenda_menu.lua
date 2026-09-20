-- Eén leader-menu voor de agenda-importmodule.
--
-- Bereikt alle acties via dezelfde Python-CLI/JSON als de terminal
-- (texttools.agenda_cli): bronnenoverzicht en -toevoegen (via agenda_bron),
-- een geplakt ## Kalender-document ontdubbelen tegen de eigen agenda (met of
-- zonder AI-normalisatie), en de eigen agenda per site op interne doublures
-- controleren. Verwijderen doet de redacteur zelf in Pubble; dit menu opent
-- hoogstens de bewerkpagina's.

local M = {}
local weekend_batches = {}
local weekend_batch_sequence = 0

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local browser = require 'ordered_browser'
local context_help = require 'context_help'

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

local weekend_editions = {
  { code = 'B', label = 'De Brug (B)' },
  { code = 'SW', label = 'De Swollenaer (SW)' },
  { code = 'ST', label = 'De Stadskoerier (ST)' },
  { code = 'D', label = 'De Drontenaar (D)' },
  { code = 'Z', label = 'Zeewolde Actueel (Z)' },
  { code = 'K', label = 'Nieuwsbode de Kop (K)' },
  { code = 'all', label = 'Alle kranten (één verzendbatch)' },
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
  return buf
end

local function open_editable(name, text)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, sanitize_lines(vim.split(text, '\n', { plain = true })))
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'hide'
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.cmd 'botright vsplit'
  vim.api.nvim_win_set_buf(0, buf)
  return buf
end

local function website_scan_help()
  return {
    title = 'Websiteartikelen zonder agenda-item',
    status = 'Overzicht van recente artikelen die mogelijk nog een agenda-item nodig hebben.',
    sections = {
      {
        heading = 'Beoordelen',
        lines = { 'o  Open het bronartikel in Pubble.' },
      },
      {
        heading = 'Agenda-item maken',
        lines = { 'Enter  Maak eerst een bewerkbaar voorstel; er wordt nog niets geplaatst.' },
      },
      {
        heading = 'Geen agenda nodig',
        lines = { 'x  Sla die beslissing op. Het websiteartikel zelf blijft bestaan.' },
      },
    },
  }
end

local function website_proposal_help(buf)
  local state = vim.b[buf].website_agenda_status
  if state == 'created' then
    return {
      title = 'Agenda-voorstel uit websiteartikel',
      status = 'Agenda-item is aangemaakt en aan het artikel gekoppeld.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { 'Controleer desgewenst het geopende agenda-item in Pubble.' },
        },
      },
    }
  elseif state == 'already-created' then
    return {
      title = 'Agenda-voorstel uit websiteartikel',
      status = 'Dit agenda-item bestond al; er is geen tweede item aangemaakt.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { 'Controleer het bestaande item via de geopende Pubble-link.' },
        },
      },
    }
  elseif state == 'partial' then
    return {
      title = 'Agenda-voorstel uit websiteartikel',
      status = 'Een deel is geplaatst; herstelmarkeringen staan in deze buffer.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { '<leader>kA  Hervat uitsluitend de ontbrekende plaatsingsstappen.' },
        },
        {
          heading = 'Let op',
          lines = { 'Verwijder de herstelmarkeringen niet en maak geen nieuw voorstel.' },
        },
      },
    }
  end
  return {
    title = 'Agenda-voorstel uit websiteartikel',
    status = 'Bewerkbaar voorstel; er is nog niets in de agenda geplaatst.',
    sections = {
      {
        heading = 'Nu doen',
        lines = { 'Controleer editie, titel, datum, tijd, locatie en omschrijving.' },
      },
      {
        heading = 'Daarna',
        lines = { '<leader>kA  Plaats het agenda-item en koppel het aan het bronartikel.' },
      },
      {
        heading = 'Let op',
        lines = { 'Het oorspronkelijke websiteartikel wordt hierbij niet herschreven.' },
      },
    },
  }
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
  local lines = {
    string.format('Eigen doublures (%s..%s)', decoded.van or '?', decoded.tot or '?'),
    string.rep('=', 40), '',
  }
  for _, e in ipairs(decoded.edities or {}) do
    if e.fout and e.fout ~= vim.NIL then
      table.insert(lines, string.format('Editie %s: NIET gelezen — %s', e.editie, e.fout))
    else
      local paren = e.paren or {}
      table.insert(lines, string.format('Editie %s: %d item(s), %d mogelijke doublure(s)%s',
        e.editie, e.aantal_items or 0, #paren, #paren > 0 and ':' or '.'))
      for _, p in ipairs(paren) do
        table.insert(lines, string.format('  %s (%s) ↔ %s — %s (%d%%)',
          p.left.title, p.left.date or '?', p.right.title, p.reason, p.score or 0))
        table.insert(lines, '      ' .. tostring(p.left.editor_url))
        table.insert(lines, '      ' .. tostring(p.right.editor_url))
      end
    end
    table.insert(lines, '')
  end
  return lines
end

function M._render_website_candidates(decoded)
  local lines = {
    string.format('Websiteartikelen zonder herkenbaar agenda-item (%s..%s)',
      decoded.date_from or '?', decoded.date_to or '?'),
    string.rep('=', 62),
    'Enter: agenda-voorstel maken · x: geen agenda nodig · o: webartikel in Pubble openen',
    '',
  }
  local by_line = {}
  for _, result in ipairs(decoded.results or {}) do
    if result.error and result.error ~= vim.NIL then
      table.insert(lines, string.format('Editie %s: NIET gelezen — %s', result.edition or '?', result.error))
    else
      local candidates = result.candidates or {}
      table.insert(lines, string.format('Editie %s: %d webartikel(en), %d volledig gecontroleerd, %d afgewezen verborgen, %d kandidaat/kandidaten%s',
        result.edition or '?', result.scanned or 0, result.details_checked or 0,
        result.rejected_hidden_count or 0, #candidates,
        #candidates > 0 and ':' or '.'))
      for _, candidate in ipairs(candidates) do
        local day = tostring(candidate.display_date or ''):sub(1, 10)
        table.insert(lines, string.format('  [%s] %s — score %d', day ~= '' and day or '?',
          candidate.headline or 'Zonder kop', candidate.score or 0))
        by_line[#lines] = candidate
      end
    end
    table.insert(lines, '')
  end
  return lines, by_line
end

local function run(cmd, stdin, on_json, on_error)
  vim.system(cmd, { text = true, stdin = stdin }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
          or 'Agenda-actie mislukt.', vim.log.levels.ERROR)
        if on_error then on_error() end
        return
      end
      local ok, decoded = pcall(vim.json.decode, vim.trim(result.stdout or ''))
      if not ok or type(decoded) ~= 'table' then
        vim.notify('Onleesbare JSON van de agenda-actie.', vim.log.levels.ERROR)
        if on_error then on_error() end
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
  local cmd = command('import', '--editie', opts.editie or 'B', '--normaliseer')
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  workflow('Agenda · verwerken (herschrijven, controleren, ontdubbelen)…', vim.log.levels.INFO)
  run(cmd, text, function(decoded)
    -- Werk de buffer bij met de herschreven agenda-teksten, mits de buffer intussen
    -- niet is gewijzigd (anders zou een late callback jouw bewerking overschrijven).
    local doc = decoded.rewritten_document
    if type(doc) == 'string' and doc ~= '' and vim.api.nvim_buf_is_valid(buf) then
      if vim.api.nvim_buf_get_changedtick(buf) == changedtick then
        local lines = sanitize_lines(vim.split(doc, '\n', { plain = true }))
        if lines[#lines] == '' then table.remove(lines) end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modified = true
      else
        vim.notify('Buffer veranderde tijdens verwerken; herschreven tekst niet toegepast.',
          vim.log.levels.WARN)
      end
    end
    open_scratch('Agenda-import', M._render_import(decoded))
  end)
end

function M.eigen_doublures()
  -- Alle eigen sites in één run (per site, niet kruislings).
  workflow('Agenda · eigen doublures zoeken (alle sites)…', vim.log.levels.INFO)
  run(command('eigen-doublures'), nil, function(decoded)
    open_scratch('Eigen doublures', M._render_pairs(decoded))
    local urls = {}
    for _, e in ipairs(decoded.edities or {}) do
      for _, p in ipairs(e.paren or {}) do
        for _, side in ipairs { p.left, p.right } do
          if side.editor_url and not vim.tbl_contains(urls, side.editor_url) then
            table.insert(urls, side.editor_url)
          end
        end
      end
    end
    browser.open_urls(urls)
    if #urls > 0 then
      workflow(#urls .. ' item(s) in de browser geopend; bekijk en verwijder zelf in Pubble.',
        vim.log.levels.INFO, { ttl = 10 })
    end
  end)
end

function M.website_voorstel(candidate)
  workflow('Agenda · voorstel uit webartikel maken…', vim.log.levels.INFO)
  run(command('website-voorstel', '--editie', candidate.edition,
    '--artikel-id', tostring(candidate.article_id)), nil, function(decoded)
    local document = decoded.document
    if type(document) ~= 'string' or document == '' then
      vim.notify('Agenda-analyse gaf geen bewerkbaar voorstel terug.', vim.log.levels.ERROR)
      return
    end
    local buf = open_editable('Agenda aanvullen ' .. tostring(candidate.article_id), document)
    vim.b[buf].website_agenda_proposal = true
    context_help.register(buf, function(target) return website_proposal_help(target) end)
    vim.keymap.set('n', '<leader>kA', function() M.website_plaatsen(buf) end, {
      buffer = buf,
      desc = '[K]rant ontbrekende [A]genda-item plaatsen',
    })
    workflow('Agenda-voorstel geopend. Controleer alle velden en plaats met <leader>kA.',
      vim.log.levels.INFO, { ttl = 10 })
  end)
end

function M.website_scan()
  workflow('Agenda · recente websiteartikelen controleren…', vim.log.levels.INFO)
  run(command('website-scan', '--editie', 'all'), nil, function(decoded)
    local lines, by_line = M._render_website_candidates(decoded)
    local buf = open_scratch('Website zonder agenda', lines)
    context_help.register(buf, website_scan_help)
    local function selected()
      return by_line[vim.api.nvim_win_get_cursor(0)[1]]
    end
    vim.keymap.set('n', '<CR>', function()
      local candidate = selected()
      if candidate then
        M.website_voorstel(candidate)
      else
        vim.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
      end
    end, { buffer = buf, desc = 'Agenda-voorstel voor webartikel maken' })
    vim.keymap.set('n', 'o', function()
      local candidate = selected()
      if candidate and candidate.editor_url then browser.open_urls { candidate.editor_url } end
    end, { buffer = buf, desc = 'Webartikel in Pubble openen' })
    vim.keymap.set('n', 'x', function()
      local line = vim.api.nvim_win_get_cursor(0)[1]
      local candidate = by_line[line]
      if not candidate then
        vim.notify('Zet de cursor op een artikelregel.', vim.log.levels.INFO)
        return
      end
      local answer = require('user_dialog').confirm(
        'Markeer "' .. tostring(candidate.headline or 'Zonder kop')
          .. '" als geen agendabericht nodig?',
        '&Ja\n&Nee',
        2
      )
      if answer ~= 1 then return end
      workflow('Agenda · afwijzing opslaan…', vim.log.levels.INFO)
      run(command('website-afwijzen', '--editie', candidate.edition,
        '--artikel-id', tostring(candidate.article_id),
        '--titel', tostring(candidate.headline or '')), nil, function(decoded_reject)
        if decoded_reject.status ~= 'rejected' then
          vim.notify(tostring(decoded_reject.reason or 'Afwijzing is niet opgeslagen.'), vim.log.levels.ERROR)
          return
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, line - 1, line, false,
            { '  ✓ Geen agenda nodig: ' .. tostring(candidate.headline or 'Zonder kop') })
          vim.bo[buf].modifiable = false
          vim.bo[buf].modified = false
          by_line[line] = nil
        end
        workflow('Gemarkeerd als geen agendabericht nodig.', vim.log.levels.INFO)
      end)
    end, { buffer = buf, desc = 'Markeer webartikel als geen agenda nodig' })
  end)
end

function M.website_plaatsen(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  workflow('Agenda · gecontroleerd item plaatsen…', vim.log.levels.INFO)
  run(command('website-plaatsen'), text, function(decoded)
    vim.b[buf].website_agenda_status = decoded.status
    vim.b[buf].website_agenda_reason = decoded.reason
    if type(decoded.updated_document) == 'string'
      and vim.api.nvim_buf_is_valid(buf)
      and vim.api.nvim_buf_get_changedtick(buf) == changedtick then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false,
        sanitize_lines(vim.split(decoded.updated_document, '\n', { plain = true })))
      vim.bo[buf].modified = true
    end
    local urls = {}
    for _, item in ipairs(decoded.created or {}) do
      if item.editor_url then table.insert(urls, item.editor_url) end
    end
    for _, item in ipairs(decoded.duplicates or {}) do
      if item.editor_url then table.insert(urls, item.editor_url) end
    end
    if #urls > 0 then browser.open_urls(urls) end
    if decoded.status == 'created' then
      workflow(string.format('%d agenda-item(s) aangemaakt en gekoppeld.', #(decoded.created or {})),
        vim.log.levels.INFO, { ttl = 10 })
    elseif decoded.status == 'already-created' then
      workflow(tostring(decoded.reason), vim.log.levels.INFO)
    elseif decoded.status == 'partial' then
      vim.notify('Een deel is geplaatst; herstelmarkeringen staan in de buffer. ' .. tostring(decoded.reason or ''),
        vim.log.levels.WARN)
    else
      vim.notify(tostring(decoded.reason or 'Agenda-item is niet geplaatst.'), vim.log.levels.WARN)
    end
  end)
end

function M.artikel_plaatsen(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  if not text:match('\n## Kalender%s*\n') and not text:match('^## Kalender%s*\n') then
    vim.notify('Geen bewerkbaar ## Kalender-blok gevonden. Maak dit eerst met <leader>ac.', vim.log.levels.WARN)
    return
  end
  local answer = require('user_dialog').confirm(
    'Alleen het gecontroleerde agenda-item versturen?\n\nKrant, websiteartikel, social en Teams worden niet verstuurd.',
    '&Ja — alleen agenda\n&Nee',
    2
  )
  if answer ~= 1 then return end

  local path = vim.api.nvim_buf_get_name(buf)
  local use_file = path ~= '' and vim.bo[buf].buftype == ''
  if use_file then
    if vim.bo[buf].modified then
      local saved = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd 'silent write' end)
      if not saved then
        vim.notify('Artikel kon niet worden opgeslagen; agenda-item is niet verstuurd.', vim.log.levels.ERROR)
        return
      end
    end
    text = nil
  end

  local cmd = use_file
      and command('artikel-plaatsen', path, '--write')
    or command('artikel-plaatsen')
  local was_modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = false
  workflow('Agenda · alleen kalenderitem plaatsen…', vim.log.levels.INFO)

  local function unlock()
    if vim.api.nvim_buf_is_valid(buf) then vim.bo[buf].modifiable = was_modifiable end
  end

  run(cmd, text, function(decoded)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = true
      if type(decoded.updated_document) == 'string' then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false,
          sanitize_lines(vim.split(decoded.updated_document, '\n', { plain = true })))
        vim.bo[buf].modified = not use_file
      end
      vim.bo[buf].modifiable = was_modifiable
      vim.b[buf].article_calendar_status = decoded.status
      vim.b[buf].article_calendar_reason = decoded.reason
    end

    local urls = {}
    for _, item in ipairs(decoded.created or {}) do
      if item.editor_url then table.insert(urls, item.editor_url) end
    end
    for _, item in ipairs(decoded.duplicates or {}) do
      if item.editor_url then table.insert(urls, item.editor_url) end
    end
    if #urls > 0 then browser.open_urls(urls) end

    if decoded.status == 'created' then
      workflow(string.format('%d agenda-item(s) geplaatst; overige publicatiekanalen zijn overgeslagen.',
        #(decoded.created or {})), vim.log.levels.INFO, { ttl = 10 })
    elseif decoded.status == 'already-created' then
      workflow(tostring(decoded.reason), vim.log.levels.INFO)
    elseif decoded.status == 'partial' then
      vim.notify('Een deel van de agenda-items is geplaatst. De ontvangen ID’s zijn opgeslagen. '
        .. tostring(decoded.reason or ''), vim.log.levels.WARN)
    else
      vim.notify(tostring(decoded.reason or 'Agenda-item is niet geplaatst.'), vim.log.levels.WARN)
    end
  end, unlock)
end

function M.weekendbericht()
  vim.ui.select(weekend_editions, {
    prompt = 'Weekendbericht maken voor welke krant?',
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    workflow('Agenda · weekendbericht maken…', vim.log.levels.INFO)
    run(command('weekendbericht', '--editie', choice.code), nil, function(decoded)
      local results = decoded.results or {}
      local opened = 0
      local opened_buffers = {}
      for _, result in ipairs(results) do
        if result.error and result.error ~= vim.NIL then
          vim.notify(string.format('%s: agenda niet gelezen — %s', result.edition or '?', result.error), vim.log.levels.ERROR)
        elseif type(result.message) == 'string' and result.message ~= '' then
          local buf = open_editable('Weekendbericht ' .. tostring(result.edition), result.message)
          table.insert(opened_buffers, { buf = buf, edition = tostring(result.edition) })
          opened = opened + 1
        end
      end
      if choice.code == 'all' and #opened_buffers > 0 then
        weekend_batch_sequence = weekend_batch_sequence + 1
        local batch_id = string.format('%d-%d', os.time(), weekend_batch_sequence)
        weekend_batches[batch_id] = {
          id = batch_id,
          sources = opened_buffers,
          now = decoded.now,
          preparing = false,
          controller = nil,
          sent = false,
        }
        for _, source in ipairs(opened_buffers) do
          vim.b[source.buf].weekend_batch_id = batch_id
          vim.b[source.buf].weekend_batch_edition = source.edition
        end
      end
      if opened > 0 then
        local message = choice.code == 'all'
            and string.format('%d aparte weekendbuffers geopend; <leader>aw in één ervan publiceert de hele batch.', opened)
          or string.format('%d weekendbericht(en) geopend; controleer en bewerk ze vóór publicatie.', opened)
        workflow(message, vim.log.levels.INFO, { ttl = 8 })
      end
    end)
  end)
end

local function mark_weekend_batch_sent(batch)
  batch.sent = true
  batch.preparing = false
  local marker = '**Weekendbatch gepubliceerd op ' .. os.date('%d-%m-%Y %H:%M') .. '**'
  for _, source in ipairs(batch.sources or {}) do
    local buf = source.buf
    if vim.api.nvim_buf_is_valid(buf) then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, 0, false, { marker, '' })
      vim.b[buf].weekend_batch_sent = true
      vim.bo[buf].modified = false
      vim.bo[buf].readonly = true
      vim.bo[buf].modifiable = false
    end
  end
  workflow(string.format(
    'Weekendbatch gepubliceerd op %d website(s).', #(batch.sources or {})
  ), vim.log.levels.INFO, { ttl = 10 })
end

function M.prepare_weekend_batch_send(buf, on_ready)
  local batch_id = vim.b[buf].weekend_batch_id
  if type(batch_id) ~= 'string' or batch_id == '' then return false end
  local batch = weekend_batches[batch_id]
  if not batch then
    vim.notify('Deze weekendbatch is niet meer compleet; maak hem opnieuw met <leader>kw.', vim.log.levels.ERROR)
    return true
  end
  if batch.sent or vim.b[buf].weekend_batch_sent == true then
    workflow('Deze weekendbatch is al gepubliceerd.', vim.log.levels.INFO)
    return true
  end
  if batch.controller and vim.api.nvim_buf_is_valid(batch.controller) then
    on_ready(batch.controller)
    return true
  end
  if batch.preparing then
    workflow('De weekendbuffers worden al samengevoegd voor publicatie.', vim.log.levels.INFO)
    return true
  end

  local messages = {}
  local ticks = {}
  for _, source in ipairs(batch.sources or {}) do
    if not vim.api.nvim_buf_is_valid(source.buf) then
      vim.notify(
        'Een buffer uit de weekendbatch is gesloten; maak de batch opnieuw met <leader>kw.',
        vim.log.levels.ERROR
      )
      return true
    end
    ticks[source.buf] = vim.api.nvim_buf_get_changedtick(source.buf)
    table.insert(messages, {
      edition = source.edition,
      message = table.concat(vim.api.nvim_buf_get_lines(source.buf, 0, -1, false), '\n'),
    })
  end

  batch.preparing = true
  workflow('Weekendbuffers samenvoegen voor één veilige publicatierun…', vim.log.levels.INFO)
  local payload = vim.json.encode { now = batch.now, messages = messages }
  vim.system(command('weekendbundel'), { text = true, stdin = payload }, function(result)
    vim.schedule(function()
      batch.preparing = false
      if result.code ~= 0 then
        vim.notify(
          vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
            or 'Weekendbuffers konden niet worden samengevoegd.',
          vim.log.levels.ERROR
        )
        return
      end
      for source_buf, changedtick in pairs(ticks) do
        if not vim.api.nvim_buf_is_valid(source_buf)
            or vim.api.nvim_buf_get_changedtick(source_buf) ~= changedtick then
          vim.notify(
            'Een weekendbuffer is tijdens de voorbereiding gewijzigd; druk opnieuw <leader>aw.',
            vim.log.levels.WARN
          )
          return
        end
      end
      local ok, decoded = pcall(vim.json.decode, vim.trim(result.stdout or ''))
      if not ok or type(decoded) ~= 'table' or type(decoded.message) ~= 'string' then
        vim.notify('Onleesbare weekendbundel van Texttools.', vim.log.levels.ERROR)
        return
      end
      local controller = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(
        controller, 0, -1, false,
        sanitize_lines(vim.split(decoded.message, '\n', { plain = true }))
      )
      vim.bo[controller].filetype = 'markdown'
      vim.bo[controller].bufhidden = 'hide'
      pcall(vim.api.nvim_buf_set_name, controller, 'Weekendbatch ' .. batch_id)
      vim.b[controller].weekend_batch_controller = batch_id
      batch.controller = controller
      local ai_text = require 'ai_text'
      ai_text.set_publication_success_hook(controller, function()
        mark_weekend_batch_sent(batch)
      end)
      on_ready(controller)
    end)
  end)
  return true
end

M._weekend_batches = weekend_batches

function M.menu()
  local bron = require 'agenda_bron'
  local items = {
    { label = 'Bronnen: overzicht', fn = function() bron.overzicht() end },
    { label = 'Bronnen: toevoegen', fn = function() bron.toevoegen() end },
    { label = 'Import: verwerken (huidige buffer)', fn = function()
      -- Altijd normaliseren naar agenda-stijl: dat is de kern van de import.
      pick_edition(function(e) M.import_check { editie = e, normaliseer = true } end)
    end },
    { label = 'Eigen agenda: doublures zoeken (alle sites)', fn = function()
      M.eigen_doublures()
    end },
    { label = 'Websiteartikelen zonder agenda-item zoeken', fn = function()
      M.website_scan()
    end },
    { label = 'Weekendbericht maken (vr t/m zo)', fn = function()
      M.weekendbericht()
    end },
  }
  vim.ui.select(items, {
    prompt = 'Agenda online',
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
    desc = '[K]rant a[g]enda online (bronnen, import, doublures)',
  })
  vim.keymap.set('n', '<leader>kw', M.weekendbericht, {
    desc = '[K]rant [w]eekendbericht uit agenda',
  })
  vim.keymap.set('n', '<leader>kA', M.artikel_plaatsen, {
    desc = '[K]rant alleen [A]genda-item uit huidige buffer plaatsen',
  })
end

M._command = command
M._sanitize_lines = sanitize_lines
M._website_scan_help = website_scan_help
M._website_proposal_help = website_proposal_help

return M
