-- krant.lua — template insertion for news articles
--
-- Place at: ~/.config/nvim/lua/krant.lua
-- In your init.lua:
--   vim.keymap.set('n', '<leader>kt', function() require('krant').menu() end, { desc = '[K]rant [T]emplate' })
--   -- which-key group:  { '<leader>k', group = '[K]rant' },

local M = {}
local texttools_commands = require('texttools_commands')
local ARTICLE_BOUNDARY = '=== ARTIKEL ==='

-- ============================================================
-- CONFIG — set this path once.
-- ============================================================
M.config = {
  -- Fixed images for specific rubrieken (Hondenhoek, Open Hof, ...).
  stock_images = vim.fn.expand('~/krant-fotos/stock'),
}

-- ============================================================
-- DATA — your templates. Adding one never requires touching the LOGIC below.
--
--   name     : menu label                                   (required)
--   text     : list of lines                                (required)
--   position : 'prepend' (default) or 'cursor'  -- ignored when {{body}} is present
--   image    : filename under M.config.stock_images, copied into the article folder
--
-- A line that is exactly {{body}} is a SEAM: lines above it go to the top of
-- the article, lines below it go to the bottom, your imported text stays in
-- the middle. Any other {{marker}} is left in place for you to fill by hand.
-- ============================================================
M.templates = {
  -- TIER 1 — plain stock text
  {
    name = 'Column Natuurvereniging',
    column = true,
    text = {
  'Column Natuurvereniging: {{title}}',
  '',
  'Maandelijks vertelt een lid van Natuurvereniging IJsseldelta in De Brug iets interessants over de natuur in onze omgeving.',
  '',
  '{{body}}',
  },
  },
   {
    name = "Kiek op de wiek (Sander de Rouwe)",
    text = {
      "De Kamper 'kiek op de wîêk' van burgemeester Sander de Rouwe",
      "",
      "In De Brug kijkt burgemeester Sander de Rouwe wekelijks in fotovorm terug op de afgelopen week.",
      "",
      "{{body}}",
    },
  },

  {
    name = 'Column Kamper Ambassadeur',
    column = true,
    -- Geen lezersnieuws-export: deze column gaat gewoon naar website + print.
    no_export = true,
    text = {
    'Kamper Ambassadeur: {{title}}',
    '',
    'Brug-columniste en oud-Kampense Margriet Vonno-Landman heeft, na vijf jaar op de Nederlandse ambassade in Singapore, een nieuwe functie bij het ministerie van Buitenlandse Zaken. Ze bezoekt Nederlandse ambassades op alle continenten en blijft in die hoedanigheid verslag doen van haar reizen, en van de verschillen en overeenkomsten met haar geboortestad Kampen. Tot de zomer van 2028 is Margriet Vonno ambassadeur van Nederland in Canada.',
    '{{body}}',
    },
  },
  {
    name = 'Column Vogelgroep Kampen',
    column = true,
    text = {
      "Column Vogelgroep Kampen: {{title}}",
      "",
      "De Vogelgroep Kampen en Omstreken zet zich in voor het welzijn van de (water)vogels in Kampen. In De Brug reflecteert zij periodiek op wat er speelt rond vogels in en rondom Kampen.",
      "",
      "{{body}}",
    },
  },
  {
    name = 'Uit de Kunst',
    column = true,
    text = {
      "Uit de Kunst",
      "",
      "Onze stad bruist van creativiteit. Sta eens stil bij al het moois dat je in onze hartelijke Hanzestad kunt zien, horen en proeven. In de rubriek Uit de Kunst tonen de organisatoren van de Inspiratieroute Kampen periodiek wat er allemaal te zien is. Deze week deelt {{naam}} {{onderwerp/toelichting}}.",
      "",
      "{{body}}",
    },
  },

 {
    name = 'Stadsdichter Berber Bouma',
    text = {
      "Stadsdichter Berber Bouma geeft woorden aan Kampen",
      "",
      "Een stadsdichter kijkt met een scherpe en vaak verrassende blik naar wat er speelt in de stad en de dorpen eromheen. Sinds de verkiezing van Bas Nijhof als eerste stadsdichter van Kampen in 2015 verschijnen in deze krant gedichten over actuele onderwerpen, grote en kleine momenten. Sinds februari 2026 vervult Berber Bouma het stadsdichterschap. De komende twee jaar verschijnen gedichten van haar hand in onze krant. Het gedicht van deze editie heet: {{titel gedicht}}.",
      "",
      "{{body}}",
    },
  },
  {
    name = 'Eregalerij kampioenen',
    no_export = true,
    text = {
      "De Brug zet kampioenen in de eregalerij",
      "",
      "Deze zomer geeft De Brug regionale kampioenen opnieuw een plek in de eregalerij. Teams en individuele sporters uit Kampen, IJsselmuiden en omgeving die dit seizoen een titel behaalden, worden met hun kampioensfoto in het zonnetje gezet. Zo maken we samen zichtbaar hoeveel sportief succes er in de regio te vieren valt. Ook op deze pagina staan weer nieuwe kampioenen. Foto's en gegevens kunnen nog steeds worden gestuurd naar redactie.debrug@brugmedia.nl onder vermelding van 'Kampioenen 2026'.",
      "",
      "{{body}}",
    },
  },

  {
    name = 'Humor met een boodschap',
    column = true,
    image = 'humor.jpg',
    no_export = true,
    text = {
      'Humor met een Boodschap: {{titel}}',
      '',
      '*(door Marcel Kalter)*',
      '{{body}}',
    },
  },

  -- TIER 3 — wraps the article body; {{Title}} stays for you to fill
  {
    name = '112 nieuws',
    no_export = true,
    text = {
      '{{prefix}} {{titel}}',
      '',
      '{{body}}',
      '',
      'Wij vinden zorgvuldige berichtgeving belangrijk en gaan zorgvuldig om met de privacy van betrokkenen. Zie je iets dat niet klopt of heb je aanvullende informatie? Mail het de redactie via redactie.debrug@brugmedia.nl.',
    },
  },

  -- ... paste your remaining rubrieken here, same shapes as above ...

  -- Ondernemen in Kampen en Raadspraat zijn dynamische templates: persoon,
  -- foto en bijschrift worden eerst gekozen. Hun menu-ingangen staan daarom
  -- in M.menu() en roepen de gespecialiseerde flows hieronder aan.
}

-- ============================================================
-- LOGIC — you should not need to edit this to add a template.
-- ============================================================

-- Scan a directory; return sorted list of entries of the given type ('file'/'directory').
local function scan_dir(path, filter_type)
  local handle = vim.uv.fs_scandir(path)
  if not handle then return {} end
  local entries = {}
  while true do
    local name, ftype = vim.uv.fs_scandir_next(handle)
    if not name then break end
    if not name:match('^%.') and (filter_type == nil or ftype == filter_type) then
      table.insert(entries, name)
    end
  end
  table.sort(entries)
  return entries
end

-- Strip YAML frontmatter (--- … ---) uit een tabel van regels.
local function strip_frontmatter(lines)
  if lines[1] ~= '---' then return lines end
  for i = 2, #lines do
    if lines[i] == '---' then
      local result = {}
      for j = i + 1, #lines do table.insert(result, lines[j]) end
      return result
    end
  end
  return lines
end

local function visible_frontmatter(lines)
  if lines[1] ~= '---' then return {} end
  local result = {}
  for i, line in ipairs(lines) do
    table.insert(result, line)
    if i > 1 and line == '---' then return result end
  end
  return {}
end

-- Splits een zichtbare pv-buffer in beschermd tagblok en artikeltekst. Oude
-- buffers zonder marker blijven als artikeltekst leesbaar; iedere template
-- bouwt bij terugschrijven vervolgens wél de nieuwe markerstructuur.
local function split_visible_article(lines)
  local content = strip_frontmatter(lines)
  for marker_index, line in ipairs(content) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      local header, article = {}, {}
      for i = 1, marker_index - 1 do
        if vim.trim(content[i]) ~= '' then table.insert(header, content[i]) end
      end
      local i = marker_index + 1
      while i <= #content and vim.trim(content[i]) == '' do i = i + 1 end
      for j = i, #content do table.insert(article, content[j]) end
      return header, article
    end
  end
  return {}, content
end

local function append_visible_article(out, header, article)
  for _, line in ipairs(header) do table.insert(out, line) end
  if #header > 0 then table.insert(out, '') end
  table.insert(out, ARTICLE_BOUNDARY)
  table.insert(out, '')
  for _, line in ipairs(article) do table.insert(out, line) end
end

-- Exports naar vormgeving bevatten alleen journalistieke tekst. YAML,
-- controlecodes en de interne artikelgrens horen uitsluitend bij de workflow.
local function visible_article_only(lines)
  local _, article = split_visible_article(lines)
  return article
end

-- Bepaal de 112-kop via dezelfde centrale plaatsentabel die pubble-send voor
-- verspreidingsgebieden gebruikt. Alleen deze template start het lokale
-- hulpproces; bij geen bekende stad/plaats blijft de veilige prefix `112:`.
local function detect_112_prefix(lines)
  local pubble_places = texttools_commands.bin('pubble-places')
  local result = vim.system(
    { pubble_places, '--json' },
    { text = true, stdin = table.concat(lines, '\n') }
  ):wait()

  if result.code == 0 then
    local ok, data = pcall(vim.fn.json_decode, result.stdout or '')
    if ok and type(data) == 'table' and type(data.primary_place) == 'string'
        and vim.trim(data.primary_place) ~= '' then
      return '112 ' .. vim.fn.toupper(vim.trim(data.primary_place)) .. ':'
    end
  end
  return '112:'
end

-- Weeknummer voor de aankomende krant: maandag = huidige week, anders volgende week.
local function publication_week()
  local weekday = tonumber(os.date('%u'))
  local ref_time = weekday == 1 and os.time() or (os.time() + 7 * 24 * 3600)
  return os.date('%V', ref_time)
end

-- Bijschrift-vorm van de partijnaam: raadsfracties heten "de <partij>-fractie",
-- maar eenmansfracties/groepen zijn geen fractie en houden hun eigen naam.
local NIET_FRACTIE = {
  ['Hart voor Kampen'] = true,
  ['Groep Azer-Zwitser'] = true,
  ['Lid Schmidt-Blokzijl'] = true,
}

local function partij_in_bijschrift(party)
  if NIET_FRACTIE[party] then return party end
  return 'de ' .. party .. '-fractie'
end

function M.raadspraat_menu()
  local base = vim.fn.expand('~/krant-fotos/raadspraat')
  local parties = scan_dir(base, 'directory')
  if #parties == 0 then
    vim.notify('Geen partijmappen gevonden in ' .. base, vim.log.levels.WARN)
    return
  end

  vim.ui.select(parties, { prompt = 'Partij:' }, function(party)
    if not party then return end

    local party_dir = base .. '/' .. party
    local all_files = scan_dir(party_dir, 'file')
    local photos = {}
    for _, f in ipairs(all_files) do
      if f:match('%.[jJ][pP][eE]?[gG]$') or f:match('%.[pP][nN][gG]$') then
        table.insert(photos, f)
      end
    end

    if #photos == 0 then
      vim.notify("Geen foto's gevonden voor " .. party, vim.log.levels.WARN)
      return
    end

    vim.ui.select(photos, { prompt = 'Persoon (' .. party .. '):' }, function(photo_file)
      if not photo_file then return end

      local naam = vim.fn.fnamemodify(photo_file, ':r')
      local photo_src = party_dir .. '/' .. photo_file

      local bijschrift = 'Deze editie van Raadspraat is geschreven door ' .. naam .. ' van ' .. partij_in_bijschrift(party) .. '.'
      local working_title = 'z - 1 Raadspraat ' .. party .. ' ' .. naam

      -- Minimal frontmatter stub — articlemeta preserves working_title and caption if set.
      local fm_lines = {
        '---',
        'newspaper:',
        '  working_title: "' .. working_title .. '"',
        '  priority: 1',
        'media:',
        '  caption: "' .. bijschrift .. '"',
        '---',
        '',
      }

      -- Template ({{body}} seam: existing buffer content stays in between)
      local template = {
        'FOTOBIJSCHRIFT: ' .. bijschrift,
        '',
        'Raadspraat ' .. party .. ':',
        '',
        '{{body}}',
        '',
        'Wilt u reageren op deze column van ' .. naam .. '? Stuur dan een reactie naar '
          .. 'redactie.debrug@brugmedia.nl met als onderwerp: Reactie Raadspraat ' .. party
          .. '. De interessantste vragen leggen wij voor aan de partij. Uw inzending en de '
          .. 'reactie van de partij publiceren we op [www.brugnieuws.nl](https://www.brugnieuws.nl) '
          .. 'of in de volgende krant.',
      }

      local before, after, in_after = {}, {}, false
      for _, l in ipairs(template) do
        if l:match('^%s*{{body}}%s*$') then
          in_after = true
        elseif not in_after then
          table.insert(before, l)
        else
          table.insert(after, l)
        end
      end

      local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      local existing_header, article_lines = split_visible_article(buf_lines)
      local new_lines = {}
      for _, l in ipairs(fm_lines) do table.insert(new_lines, l) end
      local article = {}
      for _, l in ipairs(before) do table.insert(article, l) end
      for _, l in ipairs(article_lines) do table.insert(article, l) end
      for _, l in ipairs(after) do table.insert(article, l) end
      append_visible_article(new_lines, existing_header, article)

      vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

      local week_prefix = publication_week()

      -- Save article text and photo to gemeentenieuws folder for layout/vormgeving.
      local gn_dir = vim.fn.expand('~/Desktop/' .. week_prefix .. '_gemeentenieuws')
      vim.fn.mkdir(gn_dir, 'p')
      local photo_ext = photo_file:match('%.([^%.]+)$') or 'jpg'

      vim.fn.writefile(visible_article_only(new_lines), gn_dir .. '/1.raadspraatFOTO.txt')
      vim.uv.fs_copyfile(photo_src, gn_dir .. '/1.raadspraatFOTO.' .. photo_ext)

      -- Copy photo to Pubble Inbox dropzone so <leader>aw picks it up automatically.
      local inbox = require('texttools_paths').inbox()
      vim.uv.fs_copyfile(photo_src, inbox .. '/' .. photo_file)

      vim.notify(
        'Raadspraat: ' .. naam .. ' (' .. party .. ')\n'
        .. '→ ' .. week_prefix .. '_gemeentenieuws/1.raadspraatFOTO.txt\n'
        .. '→ ' .. week_prefix .. '_gemeentenieuws/1.raadspraatFOTO.' .. photo_ext .. '\n'
        .. '→ Pubble Inbox/' .. photo_file,
        vim.log.levels.INFO
      )
    end)
  end)
end

-- Copy an image into the folder of the article you're editing (the staging
-- folder), so it travels with the text to the CMS later.
local function copy_to_staging(src)
  local dir = vim.fn.expand('%:p:h')
  if dir == '' then
    vim.notify('Save the article first so there is a folder to copy into.', vim.log.levels.WARN)
    return
  end
  local dst = dir .. '/' .. vim.fn.fnamemodify(src, ':t')
  if vim.uv.fs_copyfile(src, dst) then
    vim.notify('Image copied: ' .. vim.fn.fnamemodify(dst, ':t'))
  else
    vim.notify('Could not copy image: ' .. src, vim.log.levels.ERROR)
  end
end

-- Parse personen.md: blocks separated by blank lines, each with key: value lines.
-- Returns a table keyed by lowercase naam.
--
-- Het bestand staat in de fotomap (iCloud), niet in git. Twee dingen om te
-- weten als je een `functie:` schrijft, want die belandt via het bijschrift in
-- de YAML-frontmatter als  caption: "<tekst>"  :
--
--   \n   wordt een échte regelovergang. YAML leest dat als escape binnen
--        dubbele aanhalingstekens. Ziet eruit als een tikfout, is het niet —
--        Jenneke Palland heeft er bewust een. (Een schuine streep, /n, doet
--        niks en wordt letterlijk afgedrukt.)
--   "    breekt de frontmatter. De regel wordt hieronder simpel aan elkaar
--        geplakt, dus een dubbel aanhalingsteken sluit de caption te vroeg.
--        Gebruik ze niet in een functieomschrijving.
--
-- De `naam:` wordt letterlijk in het bijschrift overgenomen: schrijf hem dus
-- met hoofdletters, ook al is de sleutel case-insensitief.
local function parse_personen_md(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return {} end
  local result = {}
  local current = {}
  local function flush()
    if current.naam then
      result[current.naam:lower()] = current
    end
    current = {}
  end
  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed == '' then
      flush()
    else
      local k, v = trimmed:match('^([%a_]+)%s*:%s*(.+)$')
      if k and v then current[k:lower()] = vim.trim(v) end
    end
  end
  flush()
  return result
end

function M.ondernemen_menu()
  local base = vim.fn.expand('~/krant-fotos/ondernemen_in_kampen')
  local all_files = scan_dir(base, 'file')
  local photos = {}
  for _, f in ipairs(all_files) do
    if f:match('%.[jJ][pP][eE]?[gG]$') or f:match('%.[pP][nN][gG]$') then
      table.insert(photos, f)
    end
  end
  if #photos == 0 then
    vim.notify('Geen foto\'s gevonden in ' .. base, vim.log.levels.WARN)
    return
  end

  local personen = parse_personen_md(base .. '/personen.md')

  vim.ui.select(photos, { prompt = 'Ondernemen in Kampen — persoon:' }, function(photo_file)
    if not photo_file then return end

    local naam_raw = vim.fn.fnamemodify(photo_file, ':r')  -- bestandsnaam zonder extensie
    local photo_src = base .. '/' .. photo_file
    local photo_ext = photo_file:match('%.([^%.]+)$') or 'jpg'

    -- Opzoeken in personen.md (case-insensitief)
    local info = personen[naam_raw:lower()] or {}
    local naam     = info.naam or naam_raw
    local functie  = info.functie or ''
    local fotograaf = info.fotograaf or ''

    -- Zorg dat functie eindigt met een punt
    if functie ~= '' and not functie:match('%.$') then functie = functie .. '.' end

    local bijschrift = 'Deze editie van Ondernemen in Kampen is geschreven door ' .. naam .. ', ' .. functie
    local working_title = 'z - 1 Ondernemen in Kampen ' .. naam

    local fm_lines = {
      '---',
      'newspaper:',
      '  working_title: "' .. working_title .. '"',
      '  priority: 1',
      'media:',
      '  caption: "' .. bijschrift .. '"',
    }
    if fotograaf ~= '' then
      table.insert(fm_lines, '  credit: "' .. fotograaf .. '"')
    end
    table.insert(fm_lines, '---')
    table.insert(fm_lines, '')

    -- Template
    local before = {
      'Column Ondernemen in Kampen: {{titel}}',
      '',
    }
    local after = {
      '',
      'Wilt u reageren op deze column van ' .. naam .. '? Stuur dan een reactie naar '
        .. 'redactie.debrug@brugmedia.nl met als onderwerp Reactie Ondernemen in Kampen '
        .. naam .. '. De interessantste vragen leggen wij voor. Uw inzending en de reactie '
        .. 'publiceren we op [www.brugnieuws.nl](https://www.brugnieuws.nl) of eventueel in de volgende krant.',
    }

    -- Waarschuw als er al foto's in de inbox staan (voorkomt verwarring met oude foto's).
    local inbox = require('texttools_paths').inbox()
    local inbox_files = scan_dir(inbox, 'file')
    local inbox_images = {}
    for _, f in ipairs(inbox_files) do
      if f:match('%.[jJ][pP][eE]?[gG]$') or f:match('%.[pP][nN][gG]$') then
        table.insert(inbox_images, f)
      end
    end
    if #inbox_images > 0 then
      vim.notify(
        'Pubble Inbox bevat al foto\'s: ' .. table.concat(inbox_images, ', ')
          .. '\nVerwijder deze eerst om verwarring te voorkomen.',
        vim.log.levels.WARN
      )
      return
    end

    local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local existing_header, article_lines = split_visible_article(buf_lines)
    local new_lines = {}
    for _, l in ipairs(fm_lines) do table.insert(new_lines, l) end
    local article = {}
    for _, l in ipairs(before) do table.insert(article, l) end
    for _, l in ipairs(article_lines) do table.insert(article, l) end
    for _, l in ipairs(after) do table.insert(article, l) end
    append_visible_article(new_lines, existing_header, article)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

    -- Kopieer foto naar Pubble Inbox.
    local ok = vim.uv.fs_copyfile(photo_src, inbox .. '/' .. photo_file)
    if not ok then
      vim.notify('Foto kopiëren naar Pubble Inbox mislukt: ' .. photo_src, vim.log.levels.ERROR)
      return
    end

    -- Sla exportinfo op in buffervariabele; het txt-bestand wordt geschreven bij <leader>aw
    -- zodat de volledig ingevulde buffer (inclusief columntekst) wordt geëxporteerd.
    local week_prefix = publication_week()
    local gn_dir = vim.fn.expand('~/Desktop/' .. week_prefix .. '_ondernemen_in_kampen')
    vim.fn.mkdir(gn_dir, 'p')
    vim.uv.fs_copyfile(photo_src, gn_dir .. '/1.ondernemen_in_kampenFOTO.' .. photo_ext)

    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].gn_export = {
      dir      = gn_dir,
      txt_name = '1.ondernemen_in_kampenFOTO.txt',
      img_name = '1.ondernemen_in_kampenFOTO.' .. photo_ext,
    }

    vim.notify(
      'Ondernemen in Kampen: ' .. naam .. '\n'
      .. '→ Pubble Inbox/' .. photo_file .. '\n'
      .. '→ ' .. week_prefix .. '_ondernemen_in_kampen/1.ondernemen_in_kampenFOTO.' .. photo_ext .. '\n'
      .. 'Tekst wordt bij <leader>aw weggeschreven naar ondernemen in kampen.',
      vim.log.levels.INFO
    )
  end)
end

local function apply(t, vars, target_buf)
  vars = vars or {}
  target_buf = target_buf or 0

  -- Als de buffer content heeft, extraheer dan titel (eerste niet-lege regel)
  -- en body (de rest) en gebruik die voor substitutie in het template.
  local buf_lines = vim.api.nvim_buf_get_lines(target_buf, 0, -1, false)
  local existing_fm = visible_frontmatter(buf_lines)
  local existing_header, content = split_visible_article(buf_lines)
  local buf_is_empty = vim.trim(table.concat(content, '\n')) == ''

  if t.name == '112 nieuws' and not vars.prefix then
    vars.prefix = detect_112_prefix(content)
  end

  if not buf_is_empty then
    -- Eerste niet-lege regel = titel
    local title_idx = nil
    for i, l in ipairs(content) do
      if vim.trim(l) ~= '' then title_idx = i; break end
    end
    if title_idx and not vars.titel then
      vars.titel = vim.trim(content[title_idx])
    end
    -- Rest na de titel (lege regels direct erna overslaan) = body
    if not vars.body then
      local body_lines = {}
      local past_blank = false
      for i = (title_idx or 0) + 1, #content do
        if not past_blank and vim.trim(content[i]) == '' then
          -- lege regels tussen titel en body overslaan
        else
          past_blank = true
          table.insert(body_lines, content[i])
        end
      end
      vars.body = table.concat(body_lines, '\n')
    end
  end

  -- Substitueer {{key}} → waarde; meerdere regels voor {{body}}.
  local result = {}
  for _, l in ipairs(t.text) do
    if l:match('^%s*{{body}}%s*$') then
      if vars.body then
        -- Breidt een multi-line body uit over meerdere regels.
        for _, bl in ipairs(vim.split(vars.body, '\n', { plain = true })) do
          table.insert(result, bl)
        end
      end
    else
      local substituted = (l:gsub('{{(.-)}}', function(key)
        key = vim.trim(key)
        return vars[key] or ('{{' .. key .. '}}')
      end))
      table.insert(result, substituted)
    end
  end

  if t.image then
    copy_to_staging(M.config.stock_images .. '/' .. t.image)
  end

  -- Rubriek templates krijgen priority 1 (vaste rubriek = moet mee), behalve
  -- 112-berichten: die krijgen priority 2 (mag mee). De prio zit zowel in de
  -- werktitel (week - prio titel) als in newspaper.priority; beide komen uit
  -- deze inline `prio:`-regel die pubble-send verderop toepast.
  -- Columns krijgen daarnaast rubriek: column, zodat pubble-send op de
  -- website de column-slotregel eronder zet ("Wil je reageren op deze
  -- column?") i.p.v. de gewone nieuwsregel. Zie web_closing.py.
  local is_112 = t.name == '112 nieuws'
  local control = { is_112 and 'prio: 2' or 'prio: 1' }
  local replaces_rubriek = false
  if t.column then
    table.insert(control, 'rubriek: column')
    replaces_rubriek = true
  elseif is_112 then
    table.insert(control, 'rubriek: 112')
    replaces_rubriek = true
  end
  for _, line in ipairs(existing_header) do
    local key = (vim.trim(line):match('^([%a][%a%d_]*)%s*:') or ''):lower()
    local is_priority = key == 'p' or key == 'r' or key == 'prio'
    local is_replaced_rubriek = replaces_rubriek and key == 'rubriek'
    if not is_priority and not is_replaced_rubriek then
      table.insert(control, line)
    end
  end
  local final_lines = {}
  for _, line in ipairs(existing_fm) do table.insert(final_lines, line) end
  if #existing_fm > 0 then table.insert(final_lines, '') end
  append_visible_article(final_lines, control, result)
  vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, final_lines)

  -- Stel lezersnieuws export in; txt wordt geschreven bij <leader>aw.
  if not t.no_export then
    local slug = t.name:lower():gsub('[^%a%d]+', '_'):gsub('^_+', ''):gsub('_+$', '')
    local week_prefix = publication_week()
    local ln_dir = vim.fn.expand('~/Desktop/' .. week_prefix .. '_lezersnieuws')
    vim.fn.mkdir(ln_dir, 'p')
    vim.b[target_buf].gn_export = {
      dir      = ln_dir,
      txt_name = '1.' .. slug .. '.txt',
    }
  end

  vim.notify('Inserted: ' .. t.name)
end

-- Pas een template bij naam toe op een specifieke buffer, met optionele
-- vooraf ingevulde vars. Geeft true terug als het template gevonden is.
function M.apply_template_by_name(name, vars, buf)
  for _, t in ipairs(M.templates) do
    if t.name == name then
      apply(t, vars, buf)
      return true
    end
  end
  return false
end


function M.kamperkiek_flow(template)
  local inbox = require('texttools_paths').inbox()
  local all = scan_dir(inbox, 'file')
  local images = {}
  for _, f in ipairs(all) do
    if f:match('%.[jJ][pP][eE]?[gG]$') or f:match('%.[pP][nN][gG]$') then
      table.insert(images, f)
    end
  end

  if #images == 0 then
    vim.notify('Geen foto gevonden in Pubble Inbox. Zet de foto er eerst in.', vim.log.levels.ERROR)
    return
  end
  if #images > 1 then
    vim.notify('Meerdere foto\'s gevonden in Pubble Inbox. Verwijder alle foto\'s behalve de Kiek-foto.', vim.log.levels.ERROR)
    return
  end

  local photo_file = images[1]
  local photo_src = inbox .. '/' .. photo_file
  local photo_ext = photo_file:match('%.([^%.]+)$') or 'jpg'

  -- Pas de template toe op de buffer.
  apply(template)

  -- Schrijf naar gemeentenieuws map.
  local week_prefix = publication_week()
  local gn_dir = vim.fn.expand('~/Desktop/' .. week_prefix .. '_gemeentenieuws')
  vim.fn.mkdir(gn_dir, 'p')

  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.fn.writefile(visible_article_only(buf_lines), gn_dir .. '/2.kamperkiekFOTO.txt')
  vim.uv.fs_copyfile(photo_src, gn_dir .. '/2.kamperkiek.' .. photo_ext)

  vim.notify(
    'Kamper Kiek op de Wiek\n'
    .. '→ ' .. week_prefix .. '_gemeentenieuws/2.kamperkiekFOTO.txt\n'
    .. '→ ' .. week_prefix .. '_gemeentenieuws/2.kamperkiek.' .. photo_ext,
    vim.log.levels.INFO
  )
end

-- Vaste rubrieken met stockfoto → lezersnieuws export.
local stock_rubrieken = {
  {
    name        = 'Hondenhoek',
    stock_image = 'hondenhoek.jpg',
    txt_name    = '1.hondenhoekFOTO.txt',
    working_title = 'z - 1 Hondenhoek',
    template    = {
      'Hondenhoek',
      '',
      'In de column Hondenhoek belicht kynologisch gedragstherapeut en doorgewinterd hondenkenner Bert Nieuwenhuis telkens één actueel gedragsthema. Aan de hand van herkenbare voorbeelden vertaalt hij dat naar heldere, direct toepasbare tips voor een harmonieuzer leven met uw hond.',
      '',
      '{{body}}',
    },
  },
  {
    name        = 'Open Hof',
    stock_image = 'open-hof.jpg',
    txt_name    = '1.openHofFOTO.txt',
    working_title = 'z - 1 Open Hof',
    template    = {
      'Verslag Open Hof: {{title}}',
      '',
      'Wijkgemeente Open Hof, onderdeel van de Protestantse Gemeente Kampen, biedt sinds 21 november 2024 kerkasiel aan de familie Babayants, die met uitzetting wordt bedreigd. Kerkasiel is een eeuwenoude traditie waarbij kerken bescherming bieden aan mensen die vervolgd worden of dreigen te worden uitgezet. Op www.brugnieuws.nl doet voormalig predikant Kasper Jager wekelijks verslag van het kerkasiel. Ook in de krant wordt periodiek een editie opgenomen.',
      '',
      '{{body}}',
    },
  },
  {
    name        = 'Nog Even Dit',
    stock_image = 'nog-even-dit.jpg',
    txt_name    = '1.nogEvenDitFOTO.txt',
    working_title = 'z - 1 Nog Even Dit',
    template    = {
      'Nog Even Dit',
      '',
      'In de column Nog Even Dit reflecteert oud-journalist, Henk de Koning, op zijn welbekende humorvolle en ironische wijze op de zaken spelen in zijn leven en dat van zijn mede-Kampenaren.',
      '',
      '(door Henk de Koning)',
      '{{body}}',
    },
  },
}

-- Namen van templates die door een stock_rubriek_flow worden aangeboden.
local stock_rubriek_names = {}
for _, r in ipairs(stock_rubrieken) do
  stock_rubriek_names[r.name] = true
end

function M.stock_rubriek_flow(config)
  local stock_src = M.config.stock_images .. '/' .. config.stock_image
  local inbox = require('texttools_paths').inbox()

  -- Waarschuw als er al foto's in de inbox staan.
  local inbox_files = scan_dir(inbox, 'file')
  local inbox_images = {}
  for _, f in ipairs(inbox_files) do
    if f:match('%.[jJ][pP][eE]?[gG]$') or f:match('%.[pP][nN][gG]$') then
      table.insert(inbox_images, f)
    end
  end
  if #inbox_images > 0 then
    vim.notify(
      'Pubble Inbox bevat al foto\'s: ' .. table.concat(inbox_images, ', ')
        .. '\nVerwijder deze eerst om verwarring te voorkomen.',
      vim.log.levels.WARN
    )
    return
  end

  -- Minimale frontmatter stub voor working_title en priority.
  local fm_lines = {
    '---',
    'newspaper:',
    '  working_title: "' .. config.working_title .. '"',
    '  priority: 1',
    '---',
    '',
  }

  -- Verwerk {{body}} seam in template.
  local before, after, in_after = {}, {}, false
  for _, l in ipairs(config.template) do
    if l:match('^%s*{{body}}%s*$') then
      in_after = true
    elseif not in_after then
      table.insert(before, l)
    else
      table.insert(after, l)
    end
  end

  local buf_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local existing_header, article_lines = split_visible_article(buf_lines)
  local new_lines = {}
  for _, l in ipairs(fm_lines)  do table.insert(new_lines, l) end
  local article = {}
  for _, l in ipairs(before) do table.insert(article, l) end
  for _, l in ipairs(article_lines) do table.insert(article, l) end
  for _, l in ipairs(after) do table.insert(article, l) end
  append_visible_article(new_lines, existing_header, article)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

  -- Kopieer stockfoto naar Pubble Inbox.
  vim.uv.fs_copyfile(stock_src, inbox .. '/' .. config.stock_image)

  -- Maak lezersnieuws map aan en kopieer foto.
  local week_prefix = publication_week()
  local ln_dir = vim.fn.expand('~/Desktop/' .. week_prefix .. '_lezersnieuws')
  vim.fn.mkdir(ln_dir, 'p')
  local img_name = config.txt_name:gsub('%.txt$', '.jpg')
  vim.uv.fs_copyfile(stock_src, ln_dir .. '/' .. img_name)

  -- Stel gn_export in; txt-bestand wordt geschreven bij <leader>aw.
  local buf = vim.api.nvim_get_current_buf()
  vim.b[buf].gn_export = {
    dir      = ln_dir,
    txt_name = config.txt_name,
    img_name = img_name,
  }

  vim.notify(
    config.name .. '\n'
    .. '→ Pubble Inbox/' .. config.stock_image .. '\n'
    .. '→ ' .. week_prefix .. '_lezersnieuws/' .. img_name .. '\n'
    .. 'Tekst wordt bij <leader>aw weggeschreven naar lezersnieuws.',
    vim.log.levels.INFO
  )
end

function M.menu()
  local items = {
    { name = 'Raadspraat (foto + template)', _special = 'raadspraat' },
    { name = 'Ondernemen in Kampen (foto + template)', _special = 'ondernemen' },
    { name = 'Kamper Kiek op de Wiek', _special = 'kamperkiek' },
  }
  for _, r in ipairs(stock_rubrieken) do
    table.insert(items, { name = r.name, _special = 'stock_rubriek', _config = r })
  end
  local skip = { ['Kiek op de wiek (Sander de Rouwe)'] = true }
  for k in pairs(stock_rubriek_names) do skip[k] = true end
  for _, t in ipairs(M.templates) do
    if not skip[t.name] then
      table.insert(items, t)
    end
  end

  vim.ui.select(items, {
    prompt = 'Template:',
    format_item = function(t) return t.name end,
  }, function(choice)
    if not choice then return end
    if choice._special == 'stock_rubriek' then
      M.stock_rubriek_flow(choice._config)
    elseif choice._special == 'ondernemen' then
      M.ondernemen_menu()
    elseif choice._special == 'raadspraat' then
      M.raadspraat_menu()
    elseif choice._special == 'kamperkiek' then
      local kiek_template = nil
      for _, t in ipairs(M.templates) do
        if t.name == 'Kiek op de wiek (Sander de Rouwe)' then
          kiek_template = t
          break
        end
      end
      if kiek_template then
        M.kamperkiek_flow(kiek_template)
      end
    else
      apply(choice)
    end
  end)
end

return M
