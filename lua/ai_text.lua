local M = {}

-- Maak Pubble Inbox mappenstructuur aan als Keyboard Maestro een paste-bestand opent.
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function()
    local inbox = vim.fn.expand("~/Desktop/Pubble Inbox")
    vim.fn.mkdir(inbox .. "/pubble-batch", "p")
    vim.fn.mkdir(inbox .. "/published-archive", "p")
  end,
})

-- Wrap vim.system with a fidget progress handle so the user sees a spinner
-- while any AI call is running. message = '' (not omitted) shows just the
-- title + spinner, no boilerplate text — omitting it entirely would fall
-- back to fidget's own English "In progress...".
local function ai_system(cmd, opts, callback, title)
  local handle = require("fidget.progress").handle.create {
    title   = title or "AI",
    message = "",
    lsp_client = { name = "aitext" },
  }
  return vim.system(cmd, opts, function(result)
    handle:finish()
    callback(result)
  end)
end

local aitext = vim.fn.expand("~/workspace/texttools/.venv/bin/aitext")
local aichat = vim.fn.expand("~/workspace/texttools/.venv/bin/aichat")
local articlemeta = vim.fn.expand("~/workspace/texttools/.venv/bin/articlemeta")
local pubble_web_draft = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-web-draft")
local pubble_send = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-send")
local pubble_schedule = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-schedule")
local pubble_media = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-media")

local rewrite_prompts = {
  {
    label = "Rewrite to newspaper article",
    name = "journalistiek_schrijven",
    mode = "replace",
  },
}

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function run_on_visual_selection(prompt_name, append)
  local cmd

  if append then
    cmd = "'<,'>!" .. shellescape(aitext) .. " " .. shellescape(prompt_name) .. " --append"
  else
    cmd = "'<,'>!" .. shellescape(aitext) .. " " .. shellescape(prompt_name)
  end

  vim.cmd(cmd)
end

-- Detect a control flag (e.g. "calendar: x") anywhere in text, line-anchored.
local function has_control_flag(text, key)
  return text:match("^" .. key .. "%s*:%s*x%s*$") ~= nil
    or text:match("\n" .. key .. "%s*:%s*x%s*$") ~= nil
    or text:match("\n" .. key .. "%s*:%s*x%s*\n") ~= nil
    or text:match("^" .. key .. "%s*:%s*x%s*\n") ~= nil
end

-- Keys that are recognised as leading control lines (mirrors _CONTROL_KEY_PATTERN in Python).
local _control_keys = {
  p=true, r=true, e=true, b=true, c=true,
  prio=true, editie=true,
  calendar=true, cal=true,
  facebook=true, facebook_tekst=true,
  rewrite=true,
  bijschrift=true, fotograaf=true, foto=true,
}
local function _is_control_key(k)
  k = k:lower()
  if _control_keys[k] then return true end
  -- b\d+, c\d+, f\d+, bijschrift\d+, foto\d+, fotograaf\d+
  if k:match("^[bcf]%d+$") then return true end
  if k:match("^bijschrift%d+$") or k:match("^foto%d+$") or k:match("^fotograaf%d+$") then return true end
  return false
end

-- Extract the leading control block from a line table.
-- Returns saved_ctrl (raw lines), body_lines (the rest, leading blanks stripped).
-- If the buffer starts with frontmatter (---) we leave everything untouched.
local function extract_leading_control_lines(lines)
  if lines[1] == "---" then return {}, lines end
  local ctrl = {}
  local i = 1
  while i <= #lines do
    local trimmed = vim.trim(lines[i])
    if trimmed == "" then
      i = i + 1
    else
      local key = trimmed:match("^([%a][%a%d_]*)%s*:")
      if key and _is_control_key(key) then
        table.insert(ctrl, lines[i])
        i = i + 1
      else
        break
      end
    end
  end
  while i <= #lines and vim.trim(lines[i]) == "" do i = i + 1 end
  local body = {}
  for j = i, #lines do table.insert(body, lines[j]) end
  return ctrl, body
end

-- Extract YAML frontmatter lines (including both --- delimiters) from a line table.
-- Returns fm_lines (may be empty), body_start index.
local function split_frontmatter_lines(lines)
  if lines[1] ~= "---" then return {}, 1 end
  for i = 2, #lines do
    if lines[i] == "---" then
      local fm = {}
      for j = 1, i do fm[j] = lines[j] end
      return fm, i + 1
    end
  end
  return {}, 1
end

-- Strip the first leading control line matching `pattern` from the buffer.
local function strip_leading_control_line(buf, pattern)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local t = vim.trim(line)
    if t == "" then break end
    if t:match(pattern) then
      table.remove(lines, i)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return
    end
  end
end

-- Find where trailing extra sections (## Kalender / ## Facebook, in either
-- order) begin, so a full-body rewrite can replace only the article body
-- and leave sections added concurrently by <leader>ac/<leader>af intact.
-- Returns body_lines, trailing_lines (trailing_lines is {} if neither exists).
local function split_trailing_sections(lines)
  local cut = nil
  for i = 1, #lines do
    if lines[i] == "## Kalender" or lines[i] == "## Facebook" then
      cut = i
      break
    end
  end
  if not cut then return lines, {} end

  -- Walk back over the blank line + "---" separator that precedes the section.
  local body_end = cut - 1
  while body_end >= 1 and (lines[body_end] == "" or lines[body_end] == "---") do
    body_end = body_end - 1
  end

  local body = {}
  for j = 1, body_end do body[j] = lines[j] end
  local trailing = {}
  for j = body_end + 1, #lines do table.insert(trailing, lines[j]) end
  return body, trailing
end

local _run_articlemeta_calendar  -- forward declaration
local _112_signal_score          -- forward declaration
local _112_THRESHOLD = 6

local _112_DISCLAIMER = (function()
  for _, t in ipairs(require("krant").templates) do
    if t.name == "112 nieuws" then return t.text[#t.text] end
  end
  return ""
end)()

-- Detecteer 112-templatestructuur in een lijst regels.
-- Geeft terug: titel (string), body_lines (list), heeft_disclaimer (bool).
-- Geeft nil terug als het geen 112-template is.
local function _parse_112_template(lines)
  local first_content = nil
  for _, l in ipairs(lines) do
    if vim.trim(l) ~= "" then first_content = l; break end
  end
  if not first_content then return nil end
  local titel = first_content:match("^112 KAMPEN:%s*(.-)%s*$")
  if not titel then return nil end

  -- Zoek de disclaimer en extraheer de body daartussen.
  local body_lines = {}
  local heeft_disclaimer = false
  local past_title = false
  local skip_blank_after_title = true
  for _, l in ipairs(lines) do
    if not past_title then
      if l == first_content then past_title = true end
    elseif l:find(_112_DISCLAIMER:sub(1, 30), 1, true) then
      heeft_disclaimer = true
      break
    elseif skip_blank_after_title and vim.trim(l) == "" then
      -- lege regels direct na de titel overslaan
    else
      skip_blank_after_title = false
      table.insert(body_lines, l)
    end
  end
  -- Trim trailing lege regels van body
  while #body_lines > 0 and vim.trim(body_lines[#body_lines]) == "" do
    table.remove(body_lines)
  end
  return { titel = titel, body_lines = body_lines, heeft_disclaimer = heeft_disclaimer }
end

-- ---------------------------------------------------------------------------
-- Deterministische kalenderdetectie
-- Scoort artikeltekst op combinaties van datum, tijd, deelname en activiteit.
-- Sterk signaal = meerdere categorieën tegelijk; één categorie triggert nooit.
-- ---------------------------------------------------------------------------
local _CALENDAR_THRESHOLD = 8

local function _calendar_signal_score(text)
  local t = text:lower()
  local score = 0

  -- Sterke frasen: 3 pts elk (onbeperkt, maar elk patroon max 1x)
  for _, phrase in ipairs({
    "op het programma", "staat op het programma",
    "vindt plaats", "wordt gehouden", "begint om", "start om", "eindigt om",
    "de deuren gaan open", "de zaal gaat open",
    "inloop vanaf", "verzamelen om", "vertrek om",
    "aansluitend is er", "na afloop",
    "aanmelden kan", "opgeven kan", "reserveren via",
    "kaarten via", "kaarten verkrijgbaar", "tickets zijn verkrijgbaar",
    "de entree bedraagt", "toegang bedraagt", "deelname kost",
    "beperkt aantal plaatsen", "vol is vol",
    "voor alle leeftijden", "jong en oud",
    "vrije inloop", "zonder aanmelding",
    "meer informatie", "kijk voor meer informatie",
    "iedereen kan deelnemen", "iedereen kan binnenlopen",
    "onder begeleiding van",
  }) do
    if t:find(phrase, 1, true) then score = score + 3 end
  end

  -- Tijdpatronen: 3 pts elk
  if t:find("%d%d?[%.:]%d%d%s*uur") then score = score + 3 end
  if t:find("om%s+%d%d?[%.:]%d%d")  then score = score + 3 end
  if t:find("van%s+%d%d?[%.:]%d%d%s+tot") then score = score + 3 end
  if t:find("vanaf%s+%d%d?[%.:]%d%d")     then score = score + 2 end
  if t:find("aanvang%s+%d%d?")             then score = score + 2 end

  -- Weekdag + datumgetal: 2 pts (max 1x)
  for _, dag in ipairs({
    "maandag","dinsdag","woensdag","donderdag","vrijdag","zaterdag","zondag",
  }) do
    if t:find(dag .. "%s+%d") then score = score + 2; break end
  end

  -- Herhalende patronen: 2 pts
  if t:find("elke%s+%a") or t:find("iedere%s+%a")
  or t:find("wekelijks%s+op") or t:find("maandelijks%s+op") then
    score = score + 2
  end

  -- Datumpatronen: 2 pts elk (max 1x per patroon)
  if t:find("van%s+%d%d?%s+%a+%s+tot%s+en%s+met") then score = score + 2 end
  if t:find("%d%d?%s+%a+%s+%d%d%d%d")             then score = score + 2 end

  -- Deelname-/toegangswoorden: 1 pt elk, max 4
  local access = 0
  for _, word in ipairs({
    "aanmelden", "inschrijven", "reserveren", "kaartjes", "tickets",
    "gratis", "entree", "kosten", "deelname", "opgeven",
    "voorverkoop", "aanmelding", "inschrijving", "reservering",
  }) do
    if t:find(word) and access < 4 then access = access + 1 end
  end
  score = score + access

  -- Activiteitstypen: 1 pt per 2 treffers, max 3
  local act = 0
  for _, word in ipairs({
    "concert","lezing","workshop","tentoonstelling","expositie",
    "bijeenkomst","evenement","festival","excursie","wandeling",
    "cursus","training","presentatie","optreden","uitvoering",
    "voorstelling","theater","markt","toernooi","samenzang",
    "kerkdienst","filmavond","informatieavond","proeverij",
    "benefiet","jubileum","herdenking","clinic","rondleiding",
    "speurtocht","fietstocht","rondvaart","repetitie","open dag",
  }) do
    if t:find(word) then act = act + 1 end
  end
  score = score + math.min(3, math.floor(act / 2))

  return score
end

function M.rewrite_article_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Strip leading control lines BEFORE sending to AI so they are never lost or
  -- corrupted. We put them back at the top after the rewrite.
  local saved_ctrl, body_lines = extract_leading_control_lines(lines)

  -- Detecteer 112-templatestructuur: stuur alleen titel + body naar AI,
  -- niet de vaste `112 KAMPEN:` prefix en disclaimer.
  local is_112_template = _parse_112_template(body_lines)
  local input
  if is_112_template then
    input = "# " .. is_112_template.titel .. "\n\n" .. table.concat(is_112_template.body_lines, "\n")
  else
    input = table.concat(body_lines, "\n")
  end

  ai_system({ aitext, "journalistiek_schrijven" }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("AI rewrite mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return
      end

      local new_lines = vim.split(result.stdout, "\n", { plain = true })

      -- Bij 112-template: herschreven output terugzetten in de templatestructuur.
      if is_112_template then
        -- Eerste niet-lege regel = nieuwe titel (strip eventuele `# ` prefix van AI).
        local new_titel = ""
        local new_body_lines = {}
        local found_titel = false
        local skip_blank = true
        for _, l in ipairs(new_lines) do
          if not found_titel then
            local t = vim.trim(l):gsub("^#+%s*", ""):gsub("^112%s+KAMPEN:%s*", "")
            if t ~= "" then new_titel = t; found_titel = true end
          elseif skip_blank and vim.trim(l) == "" then
            -- lege regels direct na titel overslaan
          else
            skip_blank = false
            table.insert(new_body_lines, l)
          end
        end
        -- Trim trailing lege regels van body
        while #new_body_lines > 0 and vim.trim(new_body_lines[#new_body_lines]) == "" do
          table.remove(new_body_lines)
        end
        new_lines = {
          "112 KAMPEN: " .. new_titel,
          "",
        }
        for _, l in ipairs(new_body_lines) do table.insert(new_lines, l) end
        if is_112_template.heeft_disclaimer then
          table.insert(new_lines, "")
          table.insert(new_lines, _112_DISCLAIMER)
        end
      end

      -- Lees de huidige bufferinhoud opnieuw: de gebruiker kan tijdens het wachten
      -- controleregels bovenaan hebben getypt, of via <leader>ac/<leader>af al een
      -- ## Kalender-/## Facebook-sectie hebben laten toevoegen. Beide blijven behouden
      -- in plaats van overschreven door de volledige buffer-vervanging hieronder.
      local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_ctrl, current_body = extract_leading_control_lines(current_lines)
      local final_ctrl = #current_ctrl > 0 and current_ctrl or saved_ctrl
      local _, trailing_sections = split_trailing_sections(current_body)

      if #final_ctrl > 0 then
        local combined = {}
        for _, l in ipairs(final_ctrl) do table.insert(combined, l) end
        for _, l in ipairs(new_lines) do table.insert(combined, l) end
        new_lines = combined
      end

      if #trailing_sections > 0 then
        for _, l in ipairs(trailing_sections) do table.insert(new_lines, l) end
      end

      local rewritten_str = table.concat(new_lines, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      vim.b[buf].cached_metadata = nil
      vim.b[buf].cached_calendar_metadata = nil
      vim.b[buf].cached_facebook_text = nil
      vim.b[buf].pending_jobs = 0

      -- Detecteer calendar: x en facebook: x in de controleregelblok.
      local needs_calendar = false
      local needs_facebook = false
      for _, line in ipairs(final_ctrl) do
        local k, v = line:match("^(%a[%a%d_]*)%s*:%s*(.-)%s*$")
        if k and v then
          k = k:lower(); v = v:lower()
          if (k == "calendar" or k == "cal") and v == "x" then needs_calendar = true end
          if k == "facebook" and v == "x" then needs_facebook = true end
        end
      end

      -- Alle drie de achtergrondtaken starten tegelijk (vim.system is non-blocking).
      -- Elke taak schrijft naar een eigen buffervariabele — geen races.
      ai_system({ articlemeta }, { text = true, stdin = rewritten_str }, function(meta_result)
        vim.schedule(function()
          if meta_result.code ~= 0 then
            vim.notify("Metadata ophalen mislukt: " .. (meta_result.stderr or ""), vim.log.levels.WARN)
            return
          end

          local meta_lines = vim.split(meta_result.stdout, "\n", { plain = true })
          local new_fm, _ = split_frontmatter_lines(meta_lines)
          if #new_fm > 0 then
            vim.b[buf].cached_metadata = new_fm
          end
        end)
      end, "AI · Metadata")

      if needs_calendar then
        vim.b[buf].pending_jobs = (vim.b[buf].pending_jobs or 0) + 1
        ai_system({ articlemeta, "--calendar" }, { text = true, stdin = rewritten_str }, function(cal_result)
          vim.schedule(function()
            vim.b[buf].pending_jobs = math.max(0, (vim.b[buf].pending_jobs or 1) - 1)
            if cal_result.code ~= 0 then
              vim.notify("Kalendermetadata ophalen mislukt: " .. (cal_result.stderr or ""), vim.log.levels.WARN)
              return
            end
            local cal_lines = vim.split(cal_result.stdout, "\n", { plain = true })
            local cal_fm, _ = split_frontmatter_lines(cal_lines)
            if #cal_fm > 0 then
              vim.b[buf].cached_calendar_metadata = cal_fm
            end
            strip_leading_control_line(buf, "^[Cc]al[^:]*:%s*x%s*$")
          end)
        end, "AI · Kalender")
      end

      if needs_facebook then
        local fb_prompt = _112_signal_score(rewritten_str) >= _112_THRESHOLD and "facebook_bericht_112" or "facebook_bericht"
        vim.b[buf].pending_jobs = (vim.b[buf].pending_jobs or 0) + 1
        ai_system({ aitext, fb_prompt }, { text = true, stdin = rewritten_str }, function(fb_result)
          vim.schedule(function()
            vim.b[buf].pending_jobs = math.max(0, (vim.b[buf].pending_jobs or 1) - 1)
            if fb_result.code ~= 0 then
              vim.notify("Facebook-bericht ophalen mislukt: " .. (fb_result.stderr or ""), vim.log.levels.WARN)
              return
            end
            local fb_text = vim.trim(fb_result.stdout or "")
            if fb_text ~= "" then
              vim.b[buf].cached_facebook_text = fb_text
            end
            strip_leading_control_line(buf, "^[Ff]acebook%s*:%s*x%s*$")
          end)
        end, "AI · Facebook")
      end

      -- Auto-detect kalenderberichten als er geen expliciete calendar: x aanwezig is.
      if not needs_calendar then
        local cal_score = _calendar_signal_score(rewritten_str)
        if cal_score >= _CALENDAR_THRESHOLD then
          vim.notify(
            string.format("Kalenderdetectie (score %d) — kalendermetadata wordt opgehaald.", cal_score),
            vim.log.levels.INFO
          )
          _run_articlemeta_calendar(buf)
        end
      end

      -- Als dit nog geen 112-templateartikel was maar de rewritten tekst wél
      -- als 112 scoort: template alsnog toepassen (fallback voor het geval
      -- autodetect bij import gemist heeft).
      if not is_112_template then
        local already_112 = false
        for _, line in ipairs(final_ctrl) do
          local k, v = line:match("^(%a[%a%d_]*)%s*:%s*(.-)%s*$")
          if k and v and k:lower() == "rubriek" and v:lower() == "112" then
            already_112 = true; break
          end
        end
        if not already_112 and _112_signal_score(rewritten_str) >= _112_THRESHOLD then
          vim.notify("112-detectie na rewrite — template wordt toegepast.", vim.log.levels.INFO)
          require("krant").apply_template_by_name("112 nieuws", {}, buf)
          local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          table.insert(buf_lines, 1, "rubriek: 112")
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
        end
      end
    end)
  end, "AI · Herschrijven")
end

function M.visual_menu()
  vim.ui.select(rewrite_prompts, {
    prompt = "AI text action for selection:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end

    run_on_visual_selection(choice.name, choice.mode == "append")
  end)
end

vim.keymap.set("n", "<leader>ar", M.rewrite_article_buffer, {
  desc = "Rewrite to newspaper article",
})

vim.keymap.set("v", "<leader>ai", M.visual_menu, {
  desc = "AI text menu for visual selection",
})

function M.articlemeta_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")

  ai_system({ articlemeta }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local new_lines = vim.split(result.stdout, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      else
        vim.notify("articlemeta mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
      end
    end)
  end, "AI · Metadata")
end

-- Read calendar fields from YAML frontmatter lines.
local function extract_calendar_frontmatter(lines)
  local fields = {}
  local in_fm = false
  local in_calendar = false
  local dash_count = 0

  for _, line in ipairs(lines) do
    if line == "---" then
      dash_count = dash_count + 1
      if dash_count == 1 then
        in_fm = true
      elseif dash_count == 2 then
        break
      end
    elseif in_fm then
      if line:match("^calendar:") then
        in_calendar = true
      elseif in_calendar then
        if not line:match("^  ") then
          in_calendar = false
        else
          local key, val = line:match("^  ([%w_]+):%s*(.+)")
          if key and val and val ~= "null" and val ~= "~" then
            -- strip surrounding quotes that YAML may have added
            fields[key] = val:gsub("^[\"']", ""):gsub("[\"']$", "")
          end
        end
      end
    end
  end
  return fields
end

-- Build lines for the ## Kalender review section from frontmatter fields.
local function build_calendar_section_lines(lines)
  local f = extract_calendar_frontmatter(lines)
  if f.calendar_ready ~= "true" then return nil end

  local section = { "", "---", "", "## Kalender", "" }
  local function add(label, val)
    if val and val ~= "" then
      table.insert(section, label .. ": " .. val)
    end
  end

  add("Titel",    f.calendar_title or f.event_title)
  add("Datum",    f.event_date)
  add("Tijd",     f.start_time)
  add("Eindtijd", f.end_time)
  add("Locatie",  f.location_name)
  add("Stad",     f.city)

  if f.calendar_body and f.calendar_body ~= "" then
    table.insert(section, "")
    table.insert(section, f.calendar_body)
  end

  -- Section is only useful if we got at least one real field beyond the header
  if #section <= 5 then return nil end
  return section
end

-- Strip an existing ## Kalender section (and preceding --- separator).
local function strip_calendar_section(lines)
  for i = #lines, 1, -1 do
    if lines[i] == "## Kalender" then
      local cut = i - 1
      while cut >= 1 and (lines[cut] == "" or lines[cut] == "---") do
        cut = cut - 1
      end
      local result = {}
      for j = 1, cut do result[j] = lines[j] end
      return result
    end
  end
  return lines
end

-- Interne implementatie: werkt op een specifieke buf zodat autocmds en
-- leaders altijd de juiste buffer raken, ook als de focus elders is.
local function _run_articlemeta_calendar(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")

  vim.b[buf].pending_jobs = (vim.b[buf].pending_jobs or 0) + 1
  ai_system({ articlemeta, "--calendar" }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      vim.b[buf].pending_jobs = math.max(0, (vim.b[buf].pending_jobs or 1) - 1)
      if result.code ~= 0 then
        vim.notify("articlemeta mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return
      end

      local meta_lines = vim.split(result.stdout, "\n", { plain = true })

      local new_fm, _ = split_frontmatter_lines(meta_lines)
      if #new_fm > 0 then
        vim.b[buf].cached_calendar_metadata = new_fm
      end

      local section = build_calendar_section_lines(meta_lines)
      local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local base = strip_calendar_section(current)

      if section then
        for _, line in ipairs(section) do table.insert(base, line) end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, base)
        vim.notify("Kalenderdata toegevoegd. Controleer en pas aan, dan <leader>aw.", vim.log.levels.INFO)
      else
        vim.notify("Geen kalenderitem gedetecteerd in de tekst.", vim.log.levels.WARN)
      end
    end)
  end, "AI · Kalender")
end

function M.articlemeta_calendar_buffer()
  _run_articlemeta_calendar(vim.api.nvim_get_current_buf())
end

-- Kalenderdetectie bij import: vuurt op BufReadPost voor Desktop-bestanden.
-- Eénmalig per buffer (flag voorkomt herhaling bij latere saves).
local function _calendar_autodetect(buf)
  if vim.b[buf].calendar_autodetect_done then return end
  vim.b[buf].calendar_autodetect_done = true

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  local text = table.concat(lines, "\n")

  -- Sla over als calendar_article_id al een echte waarde heeft (al verwerkt).
  if text:find("calendar_article_id:") and not text:find("calendar_article_id:%s*null") then
    return
  end

  local score = _calendar_signal_score(text)
  if score >= _CALENDAR_THRESHOLD then
    vim.notify(
      string.format("Kalenderdetectie (score %d) — kalendermetadata wordt opgehaald.", score),
      vim.log.levels.INFO
    )
    _run_articlemeta_calendar(buf)
  end
end

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function(ev)
    vim.schedule(function() _calendar_autodetect(ev.buf) end)
  end,
})

-- ---------------------------------------------------------------------------
-- Deterministische 112-detectie
-- Scoort artikeltekst op signaalwoorden die typisch zijn voor 112-berichten.
-- ---------------------------------------------------------------------------
function _112_signal_score(text)
  local t = text:lower()
  local score = 0
  -- Hulpdiensten: 3 pt elk
  for _, phrase in ipairs({
    "politie", "brandweer", "ambulance", "traumahelikopter",
    "112", "reanimatie", "gereanimeerd",
    "spoedeisende", "spoedhulp",
    "hulpdiensten ter plaatse", "hulpverleners",
  }) do
    if t:find(phrase, 1, true) then score = score + 3 end
  end
  -- Incidenttypes: 2 pt elk
  for _, phrase in ipairs({
    "brand", "brandstichting", "explosie", "gaslek", "ongeluk", "aanrijding",
    "botsing", "kop-staart", "frontale botsing", "ravage", "zwaargewond",
    "lichtgewond", "slachtoffer", "omgekomen", "gewonden", "levensgevaar",
    "kritieke toestand", "ziekenhuis overgebracht", "overgebracht naar",
    "ingerekend", "aangehouden", "verdachte", "vuurwerk", "schietpartij",
    "steekpartij", "mishandeling", "beroving", "overval",
    "vermiste", "vermist", "waterongeval", "verdrinking",
    "medische noodsituatie", "reanimatie", "hartaanval",
    "bewusteloos", "bewusteloze",
  }) do
    if t:find(phrase, 1, true) then score = score + 2 end
  end
  -- Locatieprecisie: 1 pt
  if t:find("ter hoogte van") or t:find("op de hoek van") or t:find("nabij de") then
    score = score + 1
  end
  -- Tijdsprecisie: 1 pt
  if t:find("%d%d?[%.:]%d%d%s*uur") or t:find("om%s+%d%d?[%.:]%d%d") then
    score = score + 1
  end
  -- Bron: 1 pt
  if t:find("politie kampen") or t:find("IJsselland") or t:find("veiligheidsregio") then
    score = score + 1
  end
  return score
end

local function _112_autodetect(buf)
  if vim.b[buf]._112_autodetect_done then return end
  vim.b[buf]._112_autodetect_done = true
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  local text = table.concat(lines, "\n")
  -- Sla over als al als 112 gemarkeerd of al in templatevorm.
  if text:find("rubriek:%s*112") then return end
  if text:find("^112 KAMPEN:") then return end
  local score = _112_signal_score(text)
  if score < _112_THRESHOLD then return end

  vim.ui.select({ "Ja", "Nee" }, {
    prompt = string.format("112-bericht behandelen? (score %d)", score),
  }, function(choice)
    if choice ~= "Ja" then return end
    require("krant").apply_template_by_name("112 nieuws", {}, buf)
    local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    table.insert(buf_lines, 1, "rubriek: 112")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, buf_lines)
  end)
end

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function(ev)
    vim.schedule(function() _112_autodetect(ev.buf) end)
  end,
})

vim.keymap.set("n", "<leader>am", M.articlemeta_buffer, {
  desc = "Add article metadata",
})

vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Add calendar article and metadata",
})


function M.pubble_send()
  local buf = vim.api.nvim_get_current_buf()

  -- Voor raadspraat/ondernemen: opmaken (tussenkopjes + streamer) vóór verzenden.
  if vim.b[buf].gn_export and not vim.b[buf]._opmaken_done then
    vim.b[buf]._opmaken_done = true
    local pre_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    ai_system(
      { aitext, "opmaken" },
      { text = true, stdin = table.concat(pre_lines, "\n") },
      function(result)
        vim.schedule(function()
          if result.code == 0 then
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.stdout, "\n", { plain = true }))
          else
            vim.notify("Opmaken mislukt, toch verzenden...", vim.log.levels.WARN)
          end
          M.pubble_send()
        end)
      end,
      "AI · Opmaken"
    )
    return
  end
  vim.b[buf]._opmaken_done = nil

  -- Wacht tot alle achtergrondtaken (leader ar/ac/af) klaar zijn.
  if (vim.b[buf].pending_jobs or 0) > 0 then
    vim.notify("Achtergrondtaken nog bezig, even wachten...", vim.log.levels.INFO)
    vim.defer_fn(M.pubble_send, 3000)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) == "" then
    vim.notify("Huidig buffer is leeg", vim.log.levels.ERROR)
    return
  end

  -- Inject cached metadata (from background rewrite chain) if the buffer
  -- has no frontmatter yet. Calendar-metadata heeft voorrang: het is een
  -- superset van de gewone metadata (bevat ook kalender-velden).
  local cached_fm = vim.b[buf].cached_calendar_metadata or vim.b[buf].cached_metadata
  if cached_fm and #cached_fm > 0 then
    local _, body_start = split_frontmatter_lines(lines)
    if body_start == 1 then  -- no existing frontmatter in buffer
      local injected = {}
      for _, l in ipairs(cached_fm) do table.insert(injected, l) end
      table.insert(injected, "")
      for i = 1, #lines do table.insert(injected, lines[i]) end
      lines = injected
    end
  end

  -- Remember the file path so we can delete it from disk after sending.
  local file_path = vim.api.nvim_buf_get_name(buf)

  -- Detect what will be sent, so we can build the summary header afterwards.
  -- editie: B  (raw control code before <leader>am)  OR
  --   editions: B, SW  (YAML frontmatter after <leader>am)
  local editie = nil
  local has_calendar = false
  local has_facebook = false
  local pub_site_id = nil
  for _, line in ipairs(lines) do
    local e = line:match("^e:%s*(.+)$") or line:match("^editie:%s*(.+)$") or line:match("^%s*editions:%s*(.+)$")
    if e then
      local v = vim.trim(e)
      if v ~= "" and v ~= "null" then editie = v end
    end
    local s = line:match("^%s*publication_site_id:%s*['\"]?(%d+)['\"]?")
    if s then pub_site_id = tonumber(s) end
    if line:match("^## Kalender") then has_calendar = true end
    if line:match("^## Facebook") then has_facebook = true end
  end
  -- Fallback: leid de editie af uit publication_site_id als editions: null was.
  if not editie and pub_site_id then
    local site_to_code = { [19]="B", [20]="SW", [21]="ST", [24]="Z", [22]="D", [27]="K" }
    editie = site_to_code[pub_site_id]
  end

  -- Write the temp file inside Pubble Inbox so pubble-media can find photos
  -- in the same dropzone folder when --write-ids triggers the media upload.
  -- Use the original file's stem so photos get renamed to match in used/.
  local inbox = vim.fn.expand("~/Desktop/Pubble Inbox")
  local stem = (file_path ~= "") and vim.fn.fnamemodify(file_path, ":t:r") or ("verzenden-" .. os.time())
  local temp_file = inbox .. "/" .. stem .. ".md"
  -- Avoid overwriting an existing file (e.g. leftover from a failed previous run)
  local tc = 1
  while vim.fn.filereadable(temp_file) == 1 do
    temp_file = inbox .. "/" .. stem .. "-" .. tc .. ".md"
    tc = tc + 1
  end
  local using_cached_calendar = vim.b[buf].cached_calendar_metadata ~= nil
  local cached_fb = vim.b[buf].cached_facebook_text

  -- Strip Streamer: en Eindredactie: uit wat naar Pubble gaat (opmaken-artefacten
  -- voor de printontwerper, niet bedoeld als artikeltekst).
  -- Strip ook calendar:/cal: en facebook: control lines als hun cached resultaat
  -- al geïnjecteerd wordt — pubble-send hoeft ze dan niet opnieuw te draaien.
  local pubble_lines = {}
  for _, line in ipairs(lines) do
    local t = vim.trim(line)
    if t:match("^[Ss]treamer:%s*") or t:match("^Eindredactie:%s*") then
      -- altijd strippen
    elseif using_cached_calendar and t:match("^[Cc]al[^:]*:%s*x%s*$") then
      -- strip calendar: x / cal: x omdat frontmatter al klaar is
    elseif cached_fb and cached_fb ~= "" and t:match("^[Ff]acebook%s*:%s*x%s*$") then
      -- strip facebook: x omdat ## Facebook al geïnjecteerd wordt
    else
      table.insert(pubble_lines, line)
    end
  end
  -- Verwijder eventuele overtollige lege regels aan het einde.
  while #pubble_lines > 0 and vim.trim(pubble_lines[#pubble_lines]) == "" do
    table.remove(pubble_lines)
  end

  -- Injecteer gecachede Facebook-tekst als die al klaar is en er nog geen
  -- ## Facebook-sectie in de buffer staat.
  if cached_fb and cached_fb ~= "" then
    local has_fb_section = false
    for _, line in ipairs(pubble_lines) do
      if line:match("^## Facebook") then has_fb_section = true; break end
    end
    if not has_fb_section then
      for _, l in ipairs(vim.split("\n\n---\n\n## Facebook\n\n" .. cached_fb, "\n", { plain = true })) do
        table.insert(pubble_lines, l)
      end
    end
  end

  vim.fn.writefile(pubble_lines, temp_file)

  -- Bouw pubble-send-aanroep en voer hem uit (na eventuele planningsdialoog).
  local function _do_pubble_send(display_dates)
    local cmd = { pubble_send, temp_file, "--create", "--no-open", "--write-ids" }
    if next(display_dates) ~= nil then
      table.insert(cmd, "--display-dates")
      table.insert(cmd, vim.fn.json_encode(display_dates))
    end
    ai_system(cmd, { text = true }, function(result)
      vim.schedule(function()
        vim.fn.delete(temp_file)

        if result.code == 0 then
          -- Strip eventueel achtergebleven control lines uit de originele buffer.
          strip_leading_control_line(buf, "^[Cc]al[^:]*:%s*x%s*$")
          strip_leading_control_line(buf, "^[Ff]acebook%s*:%s*x%s*$")

          local output = vim.trim(result.stdout or "")
          local article_url = output:match("Pubble article: (https://[^\n]+)")
          if article_url then
            vim.ui.open(article_url)
          end

          local msg = "Verzonden naar krant: " .. (editie or "B") .. " | website"
          if has_calendar then msg = msg .. " | kalender" end
          if has_facebook then msg = msg .. " | Facebook" end
          vim.notify(msg, vim.log.levels.INFO)

          -- Exporteer volledig ingevulde buffer naar gemeentenieuws-map indien ingesteld.
          local gn = vim.b[buf].gn_export
          if gn and gn.dir and gn.txt_name then
            local export_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

            -- Haal caption en credit op uit YAML frontmatter.
            local fm_caption, fm_credit
            if export_lines[1] == "---" then
              local in_media = false
              for i = 2, #export_lines do
                if export_lines[i] == "---" then break end
                if export_lines[i]:match("^media:") then
                  in_media = true
                elseif in_media and export_lines[i]:match("^%S") then
                  in_media = false
                elseif in_media then
                  local v = export_lines[i]:match("^%s+caption:%s*\"?(.-)\"?%s*$")
                  if v and v ~= "null" and v ~= "" then fm_caption = v end
                  v = export_lines[i]:match("^%s+credit:%s*\"?(.-)\"?%s*$")
                  if v and v ~= "null" and v ~= "" then fm_credit = v end
                end
              end
            end

            -- Strip YAML frontmatter.
            if export_lines[1] == "---" then
              for i = 2, #export_lines do
                if export_lines[i] == "---" then
                  local stripped = {}
                  for j = i + 1, #export_lines do table.insert(stripped, export_lines[j]) end
                  export_lines = stripped
                  break
                end
              end
            end

            -- Extraheer Streamer en Eindredactie; verwijder ook *** + streamer-bodyregel.
            local streamer_text
            local body = {}
            local skip_next_streamer = false
            for _, line in ipairs(export_lines) do
              local trimmed = vim.trim(line)
              local s = trimmed:match("^[Ss]treamer:%s*(.+)$")
              if s then
                streamer_text = s
                -- niet toevoegen aan body
              elseif trimmed:match("^Eindredactie:%s*") then
                -- weggooien
              elseif trimmed == "***" then
                -- *** is de streamer-afscheiding; de volgende niet-lege regel is de streamertekst
                skip_next_streamer = true
              elseif skip_next_streamer then
                if trimmed ~= "" then
                  skip_next_streamer = false
                  -- deze regel IS de streamertekst in de body; weggooien (staat al bovenaan)
                else
                  -- lege regel na ***: ook weggooien
                end
              elseif trimmed:match("^>%s") or trimmed == ">" then
                -- oude blockquote-stijl (veiligheidshalve ook weggooien)
              else
                table.insert(body, line)
              end
            end

            -- Bouw header: Streamer bovenaan, dan bijschrift/credit.
            local header = {}
            if streamer_text then
              table.insert(header, "Streamer: " .. streamer_text)
            end
            if fm_caption then
              table.insert(header, "Bijschrift: " .. fm_caption)
            end
            if fm_credit then
              local credit_name = fm_credit:gsub("^[Ff]oto:%s*", "")
              table.insert(header, "Fotograaf: " .. credit_name)
            end

            -- Verwijder lege regels aan begin en einde van body.
            while #body > 0 and vim.trim(body[1]) == "" do table.remove(body, 1) end
            while #body > 0 and vim.trim(body[#body]) == "" do table.remove(body) end

            local final = {}
            for _, l in ipairs(header) do table.insert(final, l) end
            if #header > 0 then table.insert(final, "") end
            for _, l in ipairs(body) do table.insert(final, l) end

            vim.fn.writefile(final, gn.dir .. '/' .. gn.txt_name)
            vim.b[buf].gn_export = nil
          end

          -- Schrijf opgeschoonde buffer naar Pubble Inbox/published-archive/.
          -- Strip YAML frontmatter en controleregels; bewaar kop, body en Facebook.
          -- Verwijder het originele bestand op het bureaublad.
          local used_dir = inbox .. "/published-archive"
          vim.fn.mkdir(used_dir, "p")

          local clean = lines
          -- Strip YAML frontmatter (--- ... ---)
          if clean[1] == "---" then
            for i = 2, #clean do
              if clean[i] == "---" then
                local after = {}
                for j = i + 1, #clean do table.insert(after, clean[j]) end
                clean = after
                break
              end
            end
          end
          -- Strip leading control lines (e:, p:, b:, bijschrift:, etc.) and blank lines
          local ctrl = "^%s*[%a][%a%d]*%s*:"
          local s = 1
          while s <= #clean do
            local l = vim.trim(clean[s])
            if l == "" or l:match(ctrl) then s = s + 1 else break end
          end
          clean = vim.list_slice(clean, s)

          -- Prepend editie-regel
          local header = { "Editie: " .. (editie or "B"), "" }
          local out = {}
          for _, l in ipairs(header) do table.insert(out, l) end
          for _, l in ipairs(clean) do table.insert(out, l) end

          local date_prefix = os.date("%Y%m%d-%H%M%S")
          local filename = date_prefix .. "_" .. vim.fn.fnamemodify(stem .. ".md", ":t")
          local dest = used_dir .. "/" .. filename
          local counter = 1
          while vim.fn.filereadable(dest) == 1 do
            dest = used_dir .. "/" .. date_prefix .. "_" .. stem .. "-" .. counter .. ".md"
            counter = counter + 1
          end
          vim.fn.writefile(out, dest)

          -- Verwijder origineel op bureaublad; buffer blijft zichtbaar voor nacontrole.
          if file_path ~= "" and vim.fn.filereadable(file_path) == 1 then
            vim.fn.delete(file_path)
          end

          -- Zet bovenaan de (nog open) buffer wanneer verzonden is, zodat je bij
          -- meerdere open buffers in één oogopslag ziet wat al gelukt is.
          -- Opnieuw verzenden vervangt de bestaande regel i.p.v. te stapelen.
          local sent_marker = "**Verstuurd naar Pubble op " .. os.date("%d-%m-%Y %H:%M") .. "**"
          local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          if buf_lines[1] and buf_lines[1]:match("^%*%*Verstuurd naar Pubble op ") then
            vim.api.nvim_buf_set_lines(buf, 0, 1, false, { sent_marker })
          else
            vim.api.nvim_buf_set_lines(buf, 0, 0, false, { sent_marker, "" })
          end
        else
          local output = vim.trim(result.stderr or result.stdout or "")
          vim.notify(output ~= "" and output or "Pubble send mislukt", vim.log.levels.ERROR)
        end
      end)
    end,
    "Pubble · Verzenden"
    )
  end

  -- 112-berichten altijd direct plaatsen — geen planningsdialoog nodig.
  local is_112 = false
  for _, line in ipairs(pubble_lines) do
    if line:match("^112 [A-Z]") then is_112 = true; break end
  end
  if is_112 then
    _do_pubble_send({})
    return
  end

  -- Haal planningsuggesties op en toon per editie een keuze.
  -- Bij fout in pubble-schedule: toon alsnog een minimale dialog per editie.
  vim.system({ pubble_schedule, editie or "B" }, { text = true }, function(sched_result)
    vim.schedule(function()
      local display_dates = {}
      local ok, sched_data = pcall(vim.fn.json_decode, sched_result.stdout or "")
      local has_data = sched_result.code == 0 and ok and type(sched_data) == "table"

      if not has_data then
        local err = vim.trim(sched_result.stderr or "")
        vim.notify(
          "Planning ophalen mislukt" .. (err ~= "" and (": " .. err) or "") .. " — kies alsnog een optie.",
          vim.log.levels.WARN
        )
      end

      -- Edities: uit sched_data als beschikbaar, anders uit editie-string.
      local edition_codes = {}
      if has_data then
        for code, _ in pairs(sched_data) do table.insert(edition_codes, code) end
        table.sort(edition_codes)
      else
        local raw = editie or "B"
        for token in raw:gmatch("[^,]+") do
          local code = vim.trim(token):upper()
          if code ~= "" then table.insert(edition_codes, code) end
        end
      end

      -- Voeg N dagen toe aan een YYYY-MM-DD datum string.
      local function date_add_days(date_str, n)
        local y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
        if not y then return date_str end
        local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        local t2 = t + n * 86400
        return os.date("%Y-%m-%d", t2)
      end

      -- Bouw een lijst van 7 opeenvolgende dagen (als items + values),
      -- markeer de aanbevolen dag en krantendata.
      local function build_week_items(info, week_offset)
        local items = {}
        local item_values = {}
        local counts = (info and info.counts) or {}
        local suggested = info and info.suggested
        local pub_dates = (info and info.publication_dates) or {}
        -- Sla krantendatums op in een set voor snelle lookup.
        local krant_set = {}
        for _, pd in ipairs(pub_dates) do krant_set[pd] = true end

        -- Startdag: vandaag + week_offset * 7 dagen, afgerond naar middernacht.
        local base = os.time() + week_offset * 7 * 86400
        local bt = os.date("*t", base)
        bt.hour = 0; bt.min = 0; bt.sec = 0
        base = os.time(bt)

        local day_names = { "zo", "ma", "di", "wo", "do", "vr", "za" }
        for i = 0, 6 do
          local day_t = base + i * 86400
          local d = os.date("%Y-%m-%d", day_t)
          local dow = day_names[tonumber(os.date("%w", day_t)) + 1]
          local c = counts[d] or 0
          local label = d .. "  " .. dow .. "  (" .. c .. ")"
          local val
          if krant_set[d] then
            label = label .. " 🗞"
            val = d .. ":krant"
          else
            val = d .. ":" .. tostring(c)
          end
          if d == suggested then
            label = label .. " ← aanbevolen"
          end
          table.insert(items, label)
          table.insert(item_values, val)
        end
        return items, item_values, base
      end

      local function ask_edition(idx)
        if idx > #edition_codes then
          _do_pubble_send(display_dates)
          return
        end

        local code = edition_codes[idx]
        local info = has_data and sched_data[code]

        local edition_names = {
          B="De Brug", SW="De Swollenaer", ST="De Stadskoerier",
          Z="Zeewolde Actueel", D="De Drontenaar", K="De Kop van Overijssel",
        }
        local function show_week(week_offset)
          local items, item_values, base = build_week_items(info, week_offset)
          if week_offset > 0 then
            table.insert(items, "← Vorige week")
            table.insert(item_values, "__prev__")
          end
          table.insert(items, "→ Volgende week")
          table.insert(item_values, "__next__")
          table.insert(items, "Direct plaatsen")
          table.insert(item_values, "direct")

          local week_nr = tonumber(os.date("%V", base + 3 * 86400))  -- donderdag bepaalt ISO-weeknummer
          local krant_naam = edition_names[code] or code
          vim.ui.select(items, {
            prompt = krant_naam .. "  —  week " .. week_nr .. ":",
          }, function(choice, choice_idx)
            if choice == nil then
              vim.fn.delete(temp_file)
              vim.notify("Verzending geannuleerd.", vim.log.levels.INFO)
              return
            end
            local value = choice_idx and item_values[choice_idx] or "direct"
            if value == "__next__" then
              show_week(week_offset + 1)
            elseif value == "__prev__" then
              show_week(week_offset - 1)
            else
              display_dates[code] = value
              ask_edition(idx + 1)
            end
          end)
        end

        show_week(0)
      end

      ask_edition(1)
    end)
  end)
end



vim.api.nvim_create_user_command("PubbleSend", M.pubble_send, {
  desc = "Send to CMS",
})

vim.keymap.set("n", "<leader>aw", M.pubble_send, {
  desc = "Send to CMS",
})


-- Strip any previous ## Facebook varianten section appended by generate_facebook.
local function strip_facebook_section(lines)
  for i = #lines, 1, -1 do
    if lines[i] == "## Facebook" then
      local cut = i - 1
      -- strip blank lines and the preceding --- separator
      while cut >= 1 and (lines[cut] == "" or lines[cut] == "---") do
        cut = cut - 1
      end
      local result = {}
      for j = 1, cut do
        result[j] = lines[j]
      end
      return result
    end
  end
  return lines
end

function M.generate_facebook()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local clean_lines = strip_facebook_section(lines)
  local article_text = table.concat(clean_lines, "\n")
  local fb_prompt = _112_signal_score(article_text) >= _112_THRESHOLD and "facebook_bericht_112" or "facebook_bericht"

  vim.b[buf].pending_jobs = (vim.b[buf].pending_jobs or 0) + 1
  ai_system(
    { aitext, fb_prompt },
    { text = true, stdin = article_text },
    function(result)
      vim.schedule(function()
        vim.b[buf].pending_jobs = math.max(0, (vim.b[buf].pending_jobs or 1) - 1)
        if result.code ~= 0 then
          local err = vim.trim(result.stderr or result.stdout or "")
          vim.notify("Facebook AI failed: " .. (err ~= "" and err or "unknown error"), vim.log.levels.ERROR)
          return
        end

        local ai_output = vim.trim(result.stdout or "")
        if ai_output == "" then
          vim.notify("Facebook AI returned no output.", vim.log.levels.WARN)
          return
        end

        -- Lees huidige bufferinhoud zodat tussentijdse bewerkingen bewaard blijven.
        local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local base_lines = strip_facebook_section(current_lines)
        table.insert(base_lines, "")
        table.insert(base_lines, "---")
        table.insert(base_lines, "")
        table.insert(base_lines, "## Facebook")
        table.insert(base_lines, "")
        for _, line in ipairs(vim.split(ai_output, "\n", { plain = true })) do
          table.insert(base_lines, line)
        end

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, base_lines)
        vim.notify("Facebook post toegevoegd. Pas aan indien nodig, dan <leader>aw.", vim.log.levels.INFO)
      end)
    end,
    "AI · Facebook"
  )
end

vim.keymap.set("n", "<leader>af", M.generate_facebook, {
  desc = "Generate Facebook post",
})


function M.opmaken()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ai_system(
    { aitext, "opmaken" },
    { text = true, stdin = table.concat(lines, "\n") },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.stdout, "\n", { plain = true }))
          vim.b[buf]._opmaken_done = true
        else
          vim.notify("Opmaken mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        end
      end)
    end,
    "AI · Opmaken"
  )
end

vim.keymap.set("n", "<leader>ao", M.opmaken, {
  desc = "Opmaken: spellcheck, tussenkopjes, streamer",
})


-- Split buffer on the LAST "***" line.
-- Returns article (lines before ***) and prompt (text after ***), or nil if no *** found.
local function split_on_prompt_marker(lines)
  local marker_idx = nil
  for i = #lines, 1, -1 do
    if vim.trim(lines[i]) == "***" then
      marker_idx = i
      break
    end
  end
  if not marker_idx then return nil, nil end

  local article_lines = {}
  for i = 1, marker_idx - 1 do
    -- Strip trailing blank lines before the marker
    if not (i == marker_idx - 1 and vim.trim(lines[i]) == "") then
      table.insert(article_lines, lines[i])
    end
  end

  local prompt_lines = {}
  for i = marker_idx + 1, #lines do
    table.insert(prompt_lines, lines[i])
  end

  local article = table.concat(article_lines, "\n")
  local prompt = vim.trim(table.concat(prompt_lines, "\n"))
  return article, prompt
end


-- Parse conversation history from buffer.
-- Returns article text (before first ***) and a history list of {role,content} dicts.
-- User turns are delimited by ***, assistant turns by ---.
local function parse_conversation(lines)
  -- Split into blocks separated by "***" or "---"
  local article_lines = {}
  local history = {}
  local state = "article"   -- article | user | assistant
  local current_block = {}

  local function flush(role)
    local text = vim.trim(table.concat(current_block, "\n"))
    if text ~= "" then
      table.insert(history, { role = role, content = text })
    end
    current_block = {}
  end

  for _, line in ipairs(lines) do
    local trimmed = vim.trim(line)
    if trimmed == "***" then
      if state == "article" then
        article_lines = current_block
        current_block = {}
        state = "user"
      elseif state == "assistant" then
        flush("assistant")
        state = "user"
      else
        -- consecutive *** — start new user block
        flush("user")
      end
    elseif trimmed == "---" and state == "assistant" then
      -- ignore separator within assistant block
    elseif trimmed == "---" and state == "user" then
      flush("user")
      state = "assistant"
    else
      table.insert(current_block, line)
    end
  end

  -- The last block is always the current user prompt (not yet answered)
  local current_prompt = vim.trim(table.concat(current_block, "\n"))
  local article = vim.trim(table.concat(article_lines, "\n"))

  return article, history, current_prompt
end


-- <leader>ap — Ad-hoc rewrite: replace buffer with AI-rewritten text.
-- Usage: type *** on a new line, then your instruction, then press <leader>ap.
function M.ai_prompt_rewrite()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local article, prompt = split_on_prompt_marker(lines)
  if not prompt or prompt == "" then
    vim.notify("Type *** on a new line followed by your instruction first.", vim.log.levels.WARN)
    return
  end

  ai_system(
    { aichat, prompt, "--mode", "rewrite" },
    { text = true, stdin = article },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local err = vim.trim(result.stderr or result.stdout or "")
          vim.notify("aichat error: " .. (err ~= "" and err or "unknown"), vim.log.levels.ERROR)
          return
        end
        local output = vim.trim(result.stdout or "")
        if output == "" then
          vim.notify("AI returned no output.", vim.log.levels.WARN)
          return
        end
        local new_lines = vim.split(output, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)
        vim.notify("Done. Use u to undo.", vim.log.levels.INFO)
      end)
    end,
    "AI · Herschrijven"
  )
end

vim.keymap.set("n", "<leader>ap", M.ai_prompt_rewrite, {
  desc = "AI rewrite with inline prompt (*** + instruction)",
})


-- <leader>ag — AI gesprek: append AI answer below current *** prompt.
-- Builds full conversation history from prior *** / --- blocks.
function M.ai_chat()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local article, history, prompt = parse_conversation(lines)

  if prompt == "" then
    vim.notify("Type *** on a new line followed by your question first.", vim.log.levels.WARN)
    return
  end


  -- Build history JSON for the CLI. First entry in history must include the article.
  -- We embed the article in the first user message if history is empty.
  local history_arg = nil
  if #history > 0 then
    -- Prepend article context to the first user message in history.
    history[1].content = "Hier is de tekst:\n\n" .. article .. "\n\n" .. history[1].content
    local ok, encoded = pcall(vim.json.encode, history)
    if ok then history_arg = encoded end
  end

  local cmd = { aichat, prompt }
  if history_arg then
    vim.list_extend(cmd, { "--history", history_arg })
  end

  ai_system(
    cmd,
    { text = true, stdin = article },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local err = vim.trim(result.stderr or result.stdout or "")
          vim.notify("aichat error: " .. (err ~= "" and err or "unknown"), vim.log.levels.ERROR)
          return
        end
        local answer = vim.trim(result.stdout or "")
        if answer == "" then
          vim.notify("AI returned no output.", vim.log.levels.WARN)
          return
        end

        local current = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        -- Strip trailing blank lines
        while #current > 0 and vim.trim(current[#current]) == "" do
          table.remove(current)
        end
        table.insert(current, "")
        table.insert(current, "---")
        table.insert(current, "")
        for _, line in ipairs(vim.split(answer, "\n", { plain = true })) do
          table.insert(current, line)
        end
        table.insert(current, "")

        vim.api.nvim_buf_set_lines(0, 0, -1, false, current)
        -- Place cursor at end so user can type the next ***
        local last = #vim.api.nvim_buf_get_lines(0, 0, -1, false)
        vim.api.nvim_win_set_cursor(0, { last, 0 })
        vim.notify("Answer added. Type *** + next question, then <leader>ag.", vim.log.levels.INFO)
      end)
    end,
    "AI · Gesprek"
  )
end

vim.keymap.set("n", "<leader>ag", M.ai_chat, {
  desc = "AI gesprek: append answer to *** prompt",
})



-- <leader>ah — cheatsheet for article control codes (editie/prio/bijschrift/facebook).
-- One flat, fuzzy-searchable vim.ui.select list — type "edit" or "face" to filter.
-- Keep in sync with src/texttools/pubble_publications.py and pubble_batch_cli.py.
local meta_items = {
  { label = "Editie: B  - brugnieuws (standaard)", insert = "editie: B" },
  { label = "Editie: SW - deswollenaer", insert = "editie: SW" },
  { label = "Editie: ST - destadskoerier", insert = "editie: ST" },
  { label = "Editie: Z  - zeewolde", insert = "editie: Z" },
  { label = "Editie: D  - dedrontenaar", insert = "editie: D" },
  { label = "Editie: K  - De Kop van Overijssel", insert = "editie: K" },
  { label = "Editie: all - alle edities", insert = "editie: all" },
  { label = "Editie: overijssel - B, SW, ST, K", insert = "editie: overijssel" },
  { label = "Editie: flevoland - D, Z", insert = "editie: flevoland" },
  { label = "Prioriteit: 1 - moet mee", insert = "prio: 1" },
  { label = "Prioriteit: 2 - mag mee", insert = "prio: 2" },
  { label = "Prioriteit: 3 - rest (standaard)", insert = "prio: 3" },
  { label = "Prioriteit: 4 - nood", insert = "prio: 4" },
  { label = "Bijschrift: ...  (onderschrift bij de foto)", insert = "Bijschrift: " },
  { label = "Foto: ...  (naam fotograaf / credit)", insert = "Foto: " },
  { label = "Facebook: x  (AI genereert post)", insert = "facebook: x" },
  { label = "Facebook: eigen tekst  (geen AI)", insert = "facebook_tekst: " },
  { label = "Overig: rewrite: x  (herschrijven naar krantenstijl)", insert = "rewrite: x" },
  { label = "Overig: opmaken (<leader>ao) — spellcheck, tussenkopjes, streamer", insert = "" },
  { label = "Overig: controleer tekens (<leader>ak) — markeer kapotte/verdachte tekens", insert = "" },
  { label = "Overig: calendar: x  (kalenderitem meenemen)", insert = "calendar: x" },
}

local function insert_snippet_above_cursor(text)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { text })
  vim.api.nvim_win_set_cursor(0, { row, #text })
  if text:sub(-1) == " " then
    vim.cmd("startinsert!")
  end
end

function M.show_meta_cheatsheet()
  vim.ui.select(meta_items, {
    prompt = "Pubble cheatsheet:",
    format_item = function(i) return i.label end,
  }, function(item)
    if not item then return end
    insert_snippet_above_cursor(item.insert)
  end)
end

vim.keymap.set("n", "<leader>ah", M.show_meta_cheatsheet, {
  desc = "Cheatsheet: editie/prio/bijschrift/facebook codes",
})


-- <leader>a? — open texttools cheatsheet in a floating window.
function M.show_cheatsheet()
  local cheatsheet = vim.fn.expand("~/.config/nvim/texttools-cheatsheet.md")
  local lines = vim.fn.readfile(cheatsheet)

  local width = 72
  local height = math.min(#lines, vim.o.lines - 6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Texttools cheatsheet ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false

  -- Sluit met q of Escape.
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, "<cmd>close<cr>", { buffer = buf, silent = true })
  end
end

vim.keymap.set("n", "<leader>a?", M.show_cheatsheet, {
  desc = "Texttools cheatsheet",
})

return M
