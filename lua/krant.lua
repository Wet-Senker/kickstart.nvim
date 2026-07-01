-- krant.lua — template insertion for news articles
--
-- Place at: ~/.config/nvim/lua/krant.lua
-- In your init.lua:
--   vim.keymap.set('n', '<leader>kt', function() require('krant').menu() end, { desc = '[K]rant [T]emplate' })
--   -- which-key group:  { '<leader>k', group = '[K]rant' },

local M = {}

-- ============================================================
-- CONFIG — set these two paths once.
-- ============================================================
M.config = {
  -- Fixed images for specific rubrieken (Hondenhoek, Open Hof, ...).
  stock_images = vim.fn.expand('~/krant-fotos/stock'),
  -- Per-person photos for Raadspraat / Ondernemen (see note at the bottom).
  photo_db = vim.fn.expand('~/krant-fotos'),
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
    text = {
    'Kamper Ambassadeur: {{title}}',
    '',
    'Brug-columniste en oud-Kampense Margriet Vonno-Landman heeft, na vijf jaar op de Nederlandse ambassade in Singapore, een nieuwe functie bij het ministerie van Buitenlandse Zaken. Ze bezoekt Nederlandse ambassades op alle continenten en blijft in die hoedanigheid verslag doen van haar reizen, en van de verschillen en overeenkomsten met haar geboortestad Kampen. Tot de zomer van 2028 is Margriet Vonno ambassadeur van Nederland in Canada.',
    '{{body}}',
    },
  },
  {
    name = 'Column Vogelgroep Kampen',
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
    text = {
      "De Brug zet kampioenen in de eregalerij",
      "",
      "Deze zomer geeft De Brug regionale kampioenen opnieuw een plek in de eregalerij. Teams en individuele sporters uit Kampen, IJsselmuiden en omgeving die dit seizoen een titel behaalden, worden met hun kampioensfoto in het zonnetje gezet. Zo maken we samen zichtbaar hoeveel sportief succes er in de regio te vieren valt. Ook op deze pagina staan weer nieuwe kampioenen. Foto's en gegevens kunnen nog steeds worden gestuurd naar redactie.debrug@brugmedia.nl onder vermelding van 'Kampioenen 2026'.",
      "",
      "{{body}}",
    },
  },


  -- TIER 2 — stock text + a fixed image copied into the article folder
  {
    name = 'Column Hondenhoek',
    image = 'hondenhoek.jpg', -- lives in M.config.stock_images
    text = {
      'In de column Hondenhoek belicht kynologisch gedragstherapeut en doorgewinterd hondenkenner Bert Nieuwenhuis telkens één actueel gedragsthema. Aan de hand van herkenbare voorbeelden vertaalt hij dat naar heldere, direct toepasbare tips voor een harmonieuzer leven met uw hond.',
            '',
    },
  },
  {
    name = 'Verslag Open Hof',
    image = 'open-hof.jpg', -- ~/krant-fotos/stock/open-hof.jpg
    text = {
      "Verslag Open Hof: {{title}}",
      "",
      "Wijkgemeente Open Hof, onderdeel van de Protestantse Gemeente Kampen, biedt sinds 21 november 2024 kerkasiel aan de familie Babayants, die met uitzetting wordt bedreigd. Kerkasiel is een eeuwenoude traditie waarbij kerken bescherming bieden aan mensen die vervolgd worden of dreigen te worden uitgezet. Op www.brugnieuws.nl doet voormalig predikant Kasper Jager wekelijks verslag van het kerkasiel. Ook in de krant wordt periodiek een editie opgenomen.",
      "",
      "{{body}}",
    },
  },

  {
    name = 'Humor met een boodschap',
    image = 'humor', -- lives in M.config.stock_images
    text = {
      '',
            '',
    },
  },

  -- TIER 3 — wraps the article body; {{Title}} stays for you to fill
  {
    name = '112 nieuws',
    text = {
      '112 KAMPEN: {{Title}}',
      '',
      '{{body}}',
      '',
      'Dit is alle informatie die onze redactie op dit moment heeft. Wij hechten veel waarde aan zorgvuldige berichtgeving en proberen de privacy van betrokkenen zo goed mogelijk te waarborgen. Klopt iets niet, heeft u aanvullende informatie die het publieke belang dient, of vindt u dat iets anders niet voldoet aan journalistieke normen? Mail de redactie via redactie.debrug@brugmedia.nl. Uiteraard is uw privacy gewaarborgd.',
    },
  },

  -- ... paste your remaining rubrieken here, same shapes as above ...

  -- TIER 4/5 — Ondernemen in Kampen & Raadspraat: cascading menus + a
  -- per-person photo. Deliberately left out until the photo-folder layout is
  -- settled (see note at the bottom of this file).
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

      -- Copy photo to ~/Desktop/raadspraat/
      local dest_dir = vim.fn.expand('~/Desktop/raadspraat')
      vim.fn.mkdir(dest_dir, 'p')
      local photo_dst = dest_dir .. '/' .. photo_file
      if not vim.uv.fs_copyfile(photo_src, photo_dst) then
        vim.notify('Foto kopiëren mislukt: ' .. photo_src, vim.log.levels.ERROR)
        return
      end

      local bijschrift = 'Deze editie van Raadspraat is geschreven door ' .. naam .. ' van ' .. party .. '.'
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
      local new_lines = {}
      for _, l in ipairs(fm_lines) do table.insert(new_lines, l) end
      for _, l in ipairs(before) do table.insert(new_lines, l) end
      for _, l in ipairs(buf_lines) do table.insert(new_lines, l) end
      for _, l in ipairs(after) do table.insert(new_lines, l) end

      vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

      -- Save article text to gemeentenieuws folder for layout/vormgeving.
      local gn_dir = vim.fn.expand('~/Desktop/gemeentenieuws')
      vim.fn.mkdir(gn_dir, 'p')
      vim.fn.writefile(new_lines, gn_dir .. '/1.raadspraatFOTO.rtfd')
      vim.uv.fs_copyfile(photo_src, gn_dir .. '/1.RaadspraatFOTO.jpg')

      -- Copy photo to Pubble Inbox dropzone so <leader>aw picks it up automatically.
      local inbox = vim.fn.expand('~/Desktop/Pubble Inbox')
      vim.uv.fs_copyfile(photo_src, inbox .. '/' .. photo_file)

      vim.notify(
        'Raadspraat: ' .. naam .. ' (' .. party .. ')\n'
        .. '→ gemeentenieuws/1.raadspraatFOTO.rtfd\n'
        .. '→ gemeentenieuws/1.RaadspraatFOTO.jpg\n'
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

local function apply(t, vars)
  vars = vars or {}

  -- substitute {{key}} -> value; unknown keys are left as {{key}} for manual fill
  local function sub(line)
    return (line:gsub('{{(.-)}}', function(key)
      key = vim.trim(key)
      return vars[key] or ('{{' .. key .. '}}')
    end))
  end
  local lines = vim.tbl_map(sub, t.text)

  -- look for a {{body}} seam
  local before, after = lines, nil
  for i, l in ipairs(lines) do
    if l:match('^%s*{{body}}%s*$') then
      before = vim.list_slice(lines, 1, i - 1)
      after = vim.list_slice(lines, i + 1, #lines)
      break
    end
  end

  if after then -- wrap mode: above to top, below to bottom, body stays
    vim.api.nvim_buf_set_lines(0, 0, 0, false, before)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, after)
  elseif (t.position or 'prepend') == 'prepend' then
    vim.api.nvim_buf_set_lines(0, 0, 0, false, before)
  else
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, row, row, false, before)
  end

  if t.image then
    copy_to_staging(M.config.stock_images .. '/' .. t.image)
  end

  -- Rubriek templates always get priority 1 (vaste rubriek = moet mee).
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { "prio: 1", "" })

  vim.notify('Inserted: ' .. t.name)
end

function M.menu()
  local items = { { name = 'Raadspraat...', _special = 'raadspraat' } }
  for _, t in ipairs(M.templates) do table.insert(items, t) end

  vim.ui.select(items, {
    prompt = 'Template:',
    format_item = function(t) return t.name end,
  }, function(choice)
    if not choice then return end
    if choice._special == 'raadspraat' then
      M.raadspraat_menu()
    else
      apply(choice)
    end
  end)
end

M._apply = apply -- reused by the cascading Raadspraat/Ondernemen step later

return M

-- ============================================================
-- NOTE — Raadspraat & Ondernemen (to be wired next)
--
-- Idea: let the photo folder BE the database that drives the menus.
--   ~/krant-fotos/
--     ondernemen/   "Bert de Boer.jpg"   ...
--     raadspraat/
--       CDA/        "Jan Jansen.jpg"     ...
--       GroenLinks/ "Marie Pietersen.jpg" ...
--
-- Ondernemen: list files in ondernemen/  -> author menu.
-- Raadspraat: list subfolders of raadspraat/ -> party menu,
--             then files inside -> author menu.
-- The chosen file is the photo (copy_to_staging); its name fills {{naam}},
-- the folder name fills {{partij}}. Maintain the folder, never edit Lua.
-- ============================================================
