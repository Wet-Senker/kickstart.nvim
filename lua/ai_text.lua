local M = {}

-- Alleen editor-AI-processen zijn met <leader>aq annuleerbaar. Pubble-writes,
-- uploads en archivering staan bewust niet in deze lijst: die kunnen extern al
-- effect hebben gehad en moeten hun idempotente herstelroute afmaken.
local active_ai_jobs = {}
local next_ai_job_id = 0
local AI_CANCELLED = "__AI_CANCELLED__"

-- Normale workflowbevestigingen horen de redactieflow niet te onderbreken.
-- Fidget toont ze tijdelijk in een zwevend venster; vim.notify kan bij lange
-- regels terugvallen op de commandoregel en daardoor om Enter vragen.
local function notify_workflow(message)
  local ok, notification = pcall(require, "fidget.notification")
  if ok then
    notification.notify(message, vim.log.levels.INFO, {
      annote = "Pubble",
      ttl = 6,
    })
  else
    vim.notify(message, vim.log.levels.INFO)
  end
end

local OPEN_URL_IN_BACKGROUND_SCRIPT = [=[
function run(argv) {
  ObjC.import("AppKit");
  const workspace = $.NSWorkspace.sharedWorkspace;
  const previousApp = workspace.frontmostApplication;
  const configuration = $.NSWorkspaceOpenConfiguration.configuration;
  configuration.activates = false;
  const targetURL = $.NSURL.URLWithString(argv[0]);
  workspace.openURLConfigurationCompletionHandler(
    targetURL,
    configuration,
    function() {}
  );
  delay(0.6);
  previousApp.activateWithOptions($.NSApplicationActivateIgnoringOtherApps);
}
]=]

local function open_url_without_focus(url)
  vim.system(
    { "osascript", "-l", "JavaScript", "-e", OPEN_URL_IN_BACKGROUND_SCRIPT, url },
    { text = true },
    function(result)
      if result.code ~= 0 then
        vim.schedule(function()
          local err = vim.trim(result.stderr or "")
          vim.notify(
            "Pubble-pagina kon niet op de achtergrond worden geopend"
              .. (err ~= "" and (": " .. err) or "."),
            vim.log.levels.WARN
          )
        end)
      end
    end
  )
end

local function is_cancellable_ai_command(cmd)
  local executable = type(cmd) == "table" and cmd[1] or nil
  if type(executable) ~= "string" then return false end
  local name = vim.fs.basename(executable)
  return name == "aitext"
      or name == "aichat"
      or name == "articlemeta"
      or (name == "pubble-event" and cmd[2] == "teksten")
end

local function register_ai_job(buf, title)
  next_ai_job_id = next_ai_job_id + 1
  local job = {
    id = next_ai_job_id,
    buf = buf,
    title = title or "AI",
    cancelled = false,
    done = false,
  }
  active_ai_jobs[buf] = active_ai_jobs[buf] or {}
  table.insert(active_ai_jobs[buf], job)
  return job
end

local function unregister_ai_job(job)
  if not job or job.done then return end
  job.done = true
  local jobs = active_ai_jobs[job.buf]
  if not jobs then return end
  for index, candidate in ipairs(jobs) do
    if candidate == job then
      table.remove(jobs, index)
      break
    end
  end
  if #jobs == 0 then active_ai_jobs[job.buf] = nil end
end

function M.cancel_ai(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local jobs = active_ai_jobs[buf]
  if not jobs or #jobs == 0 then return false end

  local cancelled = 0
  -- Kopieer de lijst: on_exit kan tijdens/na kill dezelfde registry opschonen.
  local snapshot = {}
  for _, job in ipairs(jobs) do table.insert(snapshot, job) end
  for _, job in ipairs(snapshot) do
    local process = job.process
    if not job.cancelled and not job.done and process
        and not process:is_closing() then
      -- Zet de vlag vóór SIGTERM: een zeer snel on_exit-callback mag het late
      -- resultaat niet nog net verwerken voordat kill() terugkeert.
      job.cancelled = true
      local ok = pcall(function() process:kill("sigterm") end)
      if ok then
        cancelled = cancelled + 1
      else
        job.cancelled = false
      end
    end
  end

  if cancelled == 0 then return false end
  local send_was_waiting = vim.api.nvim_buf_is_valid(buf) and vim.b[buf].send_requested
  if vim.api.nvim_buf_is_valid(buf) then vim.b[buf].send_requested = false end
  vim.schedule(function()
    local message = cancelled == 1
        and "AI-taak geannuleerd."
        or (cancelled .. " AI-taken geannuleerd.")
    if send_was_waiting then
      message = message .. " De wachtende verzending is ook geannuleerd."
    end
    vim.notify(message, vim.log.levels.INFO)
  end)
  return true
end

-- Maak Pubble Inbox mappenstructuur aan als Keyboard Maestro een paste-bestand opent.
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function()
    local inbox = require('texttools_paths').inbox()
    vim.fn.mkdir(inbox .. "/pubble-batch", "p")
  end,
})

-- Wrap vim.system with a fidget progress handle so the user sees a spinner
-- while any AI call is running. message = '' (not omitted) shows just the
-- title + spinner, no boilerplate text — omitting it entirely would fall
-- back to fidget's own English "In progress...".
local function start_buffer_job(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.b[buf].pending_jobs = (vim.b[buf].pending_jobs or 0) + 1
  end
end

local function finish_buffer_job(buf)
  if not buf then return end
  -- De aanroeper plant zijn bufferwijziging eerst; deze schedule komt daar
  -- achter in de queue, zodat 'klaar' nooit te vroeg afgaat.
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.b[buf].pending_jobs = math.max(0, (vim.b[buf].pending_jobs or 1) - 1)
    if (vim.b[buf].pending_jobs or 0) == 0 and vim.b[buf].send_requested then
      vim.b[buf].send_requested = false
      M.pubble_send(buf)
    end
  end)
end

local function ai_system(cmd, opts, callback, title, job_buf, on_cancel)
  start_buffer_job(job_buf)
  local handle = require("fidget.progress").handle.create {
    title   = title or "AI",
    message = "",
    lsp_client = { name = "aitext" },
  }
  local ai_job = job_buf and is_cancellable_ai_command(cmd)
      and register_ai_job(job_buf, title)
      or nil
  local process = vim.system(cmd, opts, function(result)
    handle:finish()
    if ai_job then unregister_ai_job(ai_job) end
    -- Een geannuleerde call mag zijn late resultaat nooit meer in de buffer
    -- schrijven en geeft ook geen misleidende foutmelding uit de gewone callback.
    if ai_job and ai_job.cancelled then
      if on_cancel then
        local ok, err = pcall(on_cancel)
        if not ok then
          vim.schedule(function()
            vim.notify("Annuleren van AI-taak gaf een Lua-fout: " .. tostring(err), vim.log.levels.ERROR)
          end)
        end
      end
    else
      local ok, err = pcall(callback, result)
      if not ok then
        vim.schedule(function()
          vim.notify("Achtergrondtaak gaf een Lua-fout: " .. tostring(err), vim.log.levels.ERROR)
        end)
      end
    end
    finish_buffer_job(job_buf)
  end)
  if ai_job then ai_job.process = process end
  return process
end

-- Expliciete leadercombinatie: Escape blijft volledig beschikbaar voor normale
-- Vim-bediening en kan daardoor nooit per ongeluk een AI-taak stoppen.
vim.keymap.set("n", "<leader>aq", function()
  if not M.cancel_ai(vim.api.nvim_get_current_buf()) then
    vim.notify("Geen actieve AI-taak in deze buffer.", vim.log.levels.INFO)
  end
end, {
  desc = "Actieve AI-taak in huidige buffer annuleren",
})

vim.api.nvim_create_user_command("AICancel", function()
  if not M.cancel_ai(vim.api.nvim_get_current_buf()) then
    vim.notify("Geen actieve AI-taak in deze buffer.", vim.log.levels.INFO)
  end
end, { desc = "Actieve AI-taak in huidige buffer annuleren" })

local aitext = vim.fn.expand("~/workspace/texttools/.venv/bin/aitext")
local kampen_fix = vim.fn.expand("~/workspace/texttools/.venv/bin/kampen-fix")
local redactie_adres = vim.fn.expand("~/workspace/texttools/.venv/bin/redactie-adres")
local aichat = vim.fn.expand("~/workspace/texttools/.venv/bin/aichat")
local articlemeta = vim.fn.expand("~/workspace/texttools/.venv/bin/articlemeta")
local pubble_send = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-send")
local pubble_schedule = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-schedule")
local pubble_event = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-event")
local texttools_python = vim.fn.expand("~/workspace/texttools/.venv/bin/python")
local ARTICLE_BOUNDARY = "=== ARTIKEL ==="

local function shellescape(value)
  return vim.fn.shellescape(value)
end

local function run_on_visual_selection(prompt_name, append)
  local first_selected = vim.fn.line("'<")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for marker_index, line in ipairs(lines) do
    if vim.trim(line) == ARTICLE_BOUNDARY and first_selected <= marker_index then
      vim.notify(
        "Selecteer alleen artikeltekst onder " .. ARTICLE_BOUNDARY
          .. "; tags en de grens zijn beschermd.",
        vim.log.levels.ERROR
      )
      return
    end
  end

  local cmd

  if append then
    cmd = "'<,'>!" .. shellescape(aitext) .. " " .. shellescape(prompt_name) .. " --append"
  else
    cmd = "'<,'>!" .. shellescape(aitext) .. " " .. shellescape(prompt_name)
  end

  vim.cmd(cmd)
end

-- Keys that are recognised as leading control lines (mirrors _CONTROL_KEY_PATTERN in Python).
local _control_keys = {
  p=true, r=true, e=true, b=true, c=true,
  prio=true, editie=true,
  calendar=true, cal=true,
  facebook=true, facebook_tekst=true,
  rewrite=true,
  -- Credit-/bijschriftlabels — gelijk aan photo_credit's vocabulaire in Python.
  bijschrift=true, fotobijschrift=true, onderschrift=true,
  foto=true, fotograaf=true, fotografie=true, credit=true,
  fotocredit=true, fotorechten=true, beeld=true,
  rubriek=true, week=true, web=true,
}
local function _is_control_key(k)
  k = k:lower()
  if _control_keys[k] then return true end
  -- b\d+, c\d+, bijschrift\d+, foto\d+, fotograaf\d+
  if k:match("^[bc]%d+$") then return true end
  if k:match("^bijschrift%d+$") or k:match("^foto%d+$") or k:match("^fotograaf%d+$") then return true end
  return false
end

-- Splits het zichtbare tagblok van de artikeltekst. Met de nieuwe grens zijn
-- alle regels erboven beschermd; Python valideert hun betekenis centraal.
-- Zonder grens blijft alleen de oude prefixscanner als legacyfallback actief.
local function extract_leading_control_lines(lines)
  if lines[1] == "---" then return {}, lines end
  for marker_index, line in ipairs(lines) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      local ctrl = {}
      for i = 1, marker_index - 1 do
        if vim.trim(lines[i]) ~= "" then table.insert(ctrl, lines[i]) end
      end
      local body = {}
      local i = marker_index + 1
      while i <= #lines and vim.trim(lines[i]) == "" do i = i + 1 end
      for j = i, #lines do table.insert(body, lines[j]) end
      return ctrl, body, true
    end
  end
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
  return ctrl, body, false
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
  local _, body_start = split_frontmatter_lines(lines)
  local marker_index = nil
  for i = body_start, #lines do
    if vim.trim(lines[i]) == ARTICLE_BOUNDARY then marker_index = i; break end
  end
  if marker_index then
    for i = body_start, marker_index - 1 do
      if vim.trim(lines[i]):match(pattern) then
        table.remove(lines, i)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        return
      end
    end
    return
  end
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

-- DE canonieke splitser voor alle AI-leaders. Splitst bufferregels in vijf
-- structurele delen:
--   fm        YAML-frontmatter (--- ... ---)
--   ctrl      kopregels boven het artikel (e:, prio:, b:, c:, Fotograaf:, …)
--   body      de artikeltekst — het ENIGE dat ooit naar een AI mag
--   sections  staartsecties (elke ## kop: Facebook, Kalender, Suggesties, …)
--   boundary  of de verplichte zichtbare artikelgrens aanwezig was
-- Elke AI-leader hoort dit te gebruiken (input = body, resultaat terug via
-- reassemble_article), zodat een AI-run frontmatter, kopcodes en eerder
-- gegenereerde secties per constructie nooit kan beschadigen of verwijderen.
local function split_article_parts(lines)
  local fm, body_start = split_frontmatter_lines(lines)

  local rest = {}
  for i = body_start, #lines do table.insert(rest, lines[i]) end

  -- Kopregels (Fotograaf: etc.) kunnen zowel zonder als ná frontmatter staan.
  local ctrl, after_ctrl, has_boundary = extract_leading_control_lines(rest)

  local first_section = nil
  for i = 1, #after_ctrl do
    if after_ctrl[i]:match("^## %S") then
      first_section = i
      break
    end
  end
  local body_end = (first_section or (#after_ctrl + 1)) - 1
  -- Neem de ---separator en lege regels vóór de eerste sectie niet mee.
  while body_end >= 1
    and (vim.trim(after_ctrl[body_end]) == "" or vim.trim(after_ctrl[body_end]) == "---") do
    body_end = body_end - 1
  end
  local body = {}
  for i = 1, body_end do table.insert(body, after_ctrl[i]) end
  local sections = {}
  if first_section then
    for i = first_section, #after_ctrl do table.insert(sections, after_ctrl[i]) end
  end
  return fm, ctrl, body, sections, has_boundary
end

-- Verwijder een eerder ## Suggesties-blok uit de staartsecties (t/m de
-- volgende ## kop of het einde) — tekstcheck levert verse suggesties.
local function drop_suggestions_block(sections)
  local result, i = {}, 1
  while i <= #sections do
    if sections[i]:match("^## Suggesties%s*$") then
      i = i + 1
      while i <= #sections and not sections[i]:match("^## ") do i = i + 1 end
    else
      table.insert(result, sections[i])
      i = i + 1
    end
  end
  while #result > 0 and (vim.trim(result[#result]) == "" or vim.trim(result[#result]) == "---") do
    table.remove(result)
  end
  return result
end

local function reassemble_article(fm, ctrl, body, sections, has_boundary)
  local out = {}
  for _, l in ipairs(fm) do table.insert(out, l) end
  if #fm > 0 then table.insert(out, "") end
  for _, l in ipairs(ctrl) do table.insert(out, l) end
  if #ctrl > 0 then table.insert(out, "") end
  if has_boundary then
    table.insert(out, ARTICLE_BOUNDARY)
    table.insert(out, "")
  end
  for _, l in ipairs(body) do table.insert(out, l) end
  if #sections > 0 then
    table.insert(out, "")
    table.insert(out, "---")
    table.insert(out, "")
    for _, l in ipairs(sections) do table.insert(out, l) end
  end
  return out
end

-- Losse globale fotometadata hoort bij de beschermde controleregels, nooit bij
-- de artikeltekst. De AI kan zowel credit als bijschrift uit de bron halen;
-- herken alleen volledige zelfstandige regels en normaliseer hun labels.
-- Labelvocabulaire gelijk aan photo_credit (Python). De Lua-matcher pakt
-- alleen losse woorden (`^([%a]+):`), dus meerwoord-/apostroflabels als
-- "beeld en tekst" en "foto's" vallen hier bewust buiten.
local _media_control_kinds = {
  b = "caption",
  bijschrift = "caption",
  fotobijschrift = "caption",
  onderschrift = "caption",
  c = "photographer",
  credit = "photographer",
  foto = "photographer",
  fotograaf = "photographer",
  fotografie = "photographer",
  fotocredit = "photographer",
  fotorechten = "photographer",
  beeld = "photographer",
}

local function extract_media_controls(body)
  local cleaned = {}
  local media = {}

  for _, line in ipairs(body) do
    local key, value = vim.trim(line):match("^([%a]+)%s*:%s*(.-)%s*$")
    local kind = key and _media_control_kinds[key:lower()] or nil
    if kind and value ~= "" then
      if not media[kind] then
        if kind == "caption" then
          media[kind] = "Bijschrift: " .. value
        else
          value = value:gsub("^[Ff][Oo][Tt][Oo]%s*:%s*", "")
          media[kind] = "Foto: " .. value
        end
      end
    else
      table.insert(cleaned, line)
    end
  end

  while #cleaned > 0 and vim.trim(cleaned[1]) == "" do table.remove(cleaned, 1) end
  while #cleaned > 0 and vim.trim(cleaned[#cleaned]) == "" do table.remove(cleaned) end
  return cleaned, media
end

local function has_media_control(ctrl, wanted_kind)
  for _, line in ipairs(ctrl) do
    local key = vim.trim(line):match("^([%a]+)%s*:")
    if key and _media_control_kinds[key:lower()] == wanted_kind then return true end
  end
  return false
end

local function add_media_controls(ctrl, media)
  local result = {}
  for _, line in ipairs(ctrl) do table.insert(result, line) end
  -- Houd dezelfde zichtbare volgorde aan als de rewriteprompt: foto, bijschrift.
  for _, kind in ipairs({ "photographer", "caption" }) do
    if media[kind] and not has_media_control(ctrl, kind) then
      table.insert(result, media[kind])
    end
  end
  return result
end

-- Kleine inspecteerbare testpunten voor regressietests van de grenslogica.
M._extract_media_controls = extract_media_controls
M._add_media_controls = add_media_controls

local _run_articlemeta_calendar  -- forward declaration
local _112_signal_score          -- forward declaration
local _offer_112_template        -- forward declaration
local _112_THRESHOLD = 6

local _112_DISCLAIMER = (function()
  for _, t in ipairs(require("krant").templates) do
    if t.name == "112 nieuws" then return t.text[#t.text] end
  end
  return ""
end)()

-- Detecteer 112-templatestructuur in een lijst regels.
-- Geeft terug: prefix/titel, body_lines en heeft_disclaimer.
-- Geeft nil terug als het geen 112-template is.
local function _parse_112_template(lines)
  local first_content = nil
  for _, l in ipairs(lines) do
    if vim.trim(l) ~= "" then first_content = l; break end
  end
  if not first_content then return nil end
  local prefix, titel = first_content:match("^(112:%s*)(.-)%s*$")
  if not titel then
    prefix, titel = first_content:match("^(112%s+[^:]+:%s*)(.-)%s*$")
  end
  if not titel then return nil end
  prefix = vim.trim(prefix)

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
  return {
    prefix = prefix,
    titel = titel,
    body_lines = body_lines,
    heeft_disclaimer = heeft_disclaimer,
  }
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
    "opgeven kan", "reserveren via",
    "kaarten via", "kaarten verkrijgbaar", "tickets zijn verkrijgbaar",
    "de entree bedraagt", "toegang bedraagt", "deelname kost",
    "beperkt aantal plaatsen", "vol is vol",
    "voor alle leeftijden", "jong en oud",
    "vrije inloop", "zonder aanmelding",
    "kijk voor meer informatie",
    "iedereen kan deelnemen", "iedereen kan binnenlopen",
    "onder begeleiding van",
  }) do
    if t:find(phrase, 1, true) then score = score + 3 end
  end

  -- Tijdpatronen. Eén kloktijd telt één keer (+3), of hij nu als "om 7.30",
  -- "7.30 uur" of "om 7.30 uur" geschreven is — anders telt de volledige vorm
  -- dubbel (het uur-patroon én het om-patroon voldoen allebei).
  if t:find("om%s+%d%d?[%.:]%d%d") or t:find("%d%d?[%.:]%d%d%s*uur") then
    score = score + 3
  end
  -- Een tijdvenster (van .. tot) is een sterker evenementsignaal: extra.
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

-- Vul (of vervang) de e:-controleregel op basis van dateline + plaatsenscan.
-- Draait direct na het herschrijven (<leader>ar) — dan is er een dateline en
-- een redelijk complete tekst. De regel wordt: `e: <kranten>, SUGGESTIE,
-- <suggesties>`. pubble-send negeert bij het versturen alles vanaf SUGGESTIE,
-- dus een suggestie gaat pas mee als de gebruiker die vóór SUGGESTIE zet.
-- Puur een hulpje: bij een fout stil overslaan, nooit de herschrijving breken.
local function fill_editions_line(buf, content)
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), tmp)
  start_buffer_job(buf)
  vim.system(
    { pubble_send, tmp, "--resolve-editions", "--require-article-boundary" },
    { text = true },
    function(res)
    vim.schedule(function()
      vim.fn.delete(tmp)
      local ok, r = pcall(vim.fn.json_decode, res.stdout or "")
      if res.code ~= 0 or not ok or type(r) ~= "table" or type(r.editions) ~= "table" then
        return
      end

      -- Gekozen kranten eerst, daarna de suggesties (dedup, niet al gekozen).
      local seen, chosen, suggested = {}, {}, {}
      for _, code in ipairs(r.editions) do
        if not seen[code] then seen[code] = true; table.insert(chosen, code) end
      end
      if type(r.suggestions) == "table" then
        for _, s in ipairs(r.suggestions) do
          for _, code in ipairs(s.editions or {}) do
            if not seen[code] then seen[code] = true; table.insert(suggested, code) end
          end
        end
      end
      if #chosen == 0 then return end

      local e_line = "e: " .. table.concat(chosen, ", ")
      if #suggested > 0 then
        e_line = e_line .. ", SUGGESTIE, " .. table.concat(suggested, ", ")
      end

      -- Geen dateline herkend → e: valt terug op De Brug. Dat is precies de
      -- stille misser die een artikel per ongeluk naar B stuurt; hier, waar de
      -- e:-regel ontstaat, expliciet waarschuwen zodat het opvalt.
      if type(r.source) == "string" and r.source:match("^standaard") then
        vim.notify(
          "LET OP: geen dateline herkend — e: staat standaard op De Brug. Klopt dat niet, pas e: aan.",
          vim.log.levels.WARN
        )
      end

      -- Bestaande e:/editie:-regel vervangen, anders bovenaan de controleregels.
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)

      local new_ctrl = { e_line }
      for _, l in ipairs(ctrl) do
        local key = vim.trim(l):match("^([%a][%a%d_]*)%s*:")
        if not (key and (key:lower() == "e" or key:lower() == "editie")) then
          table.insert(new_ctrl, l)
        end
      end

      local out = reassemble_article(fm, new_ctrl, body, sections, has_boundary)

      -- Zet meteen het juiste redactie-mailadres voor de primaire editie
      -- (deterministisch, geen AI): net zo automatisch als de dateline zelf.
      -- Zo staat er onder een 112-/column-artikel voor Steenwijk direct
      -- redactiedekop@… i.p.v. de De Brug-default. De web-omzetting naar
      -- "via de knoppen hieronder" blijft een verzendstap.
      local primary = chosen[1]
      if primary then
        local adapted = vim.system(
          { redactie_adres, "--editie", primary },
          { text = true, stdin = table.concat(out, "\n") }
        ):wait(3000)
        if adapted.code == 0 and adapted.stdout and adapted.stdout ~= "" then
          out = vim.split((adapted.stdout:gsub("\n$", "")), "\n", { plain = true })
        end
      end

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
    end)
    finish_buffer_job(buf)
    end
  )
end

function M.rewrite_article_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Eén canonieke split: frontmatter, tagblok, grens en staartsecties blijven
  -- buiten de AI-input en worden na de rewrite deterministisch teruggezet.
  local saved_fm, saved_ctrl, body_lines, saved_sections, saved_boundary =
    split_article_parts(lines)

  -- Expliciete foto-/bijschriftregels uit de bron hoeven niet door AI verplaatst
  -- te worden. Haal ze vóór de call uit de body; mediaregels die de AI uit
  -- lopende tekst afleidt worden na de call via dezelfde helper afgevangen.
  local source_media
  body_lines, source_media = extract_media_controls(body_lines)

  -- Detecteer 112-templatestructuur: stuur alleen titel + body naar AI,
  -- niet de plaatsafhankelijke `112 <PLAATS>:` prefix en disclaimer.
  local is_112_template = _parse_112_template(body_lines)
  local input
  if is_112_template then
    input = "# " .. is_112_template.titel .. "\n\n" .. table.concat(is_112_template.body_lines, "\n")
  else
    input = table.concat(body_lines, "\n")
  end

  -- Rewrite gevolgd door de gerichte Kampen-correctie (kampen-fix). Die is
  -- deterministisch gepoort op "Kampense", dus zonder dat woord komt de tekst
  -- instant onveranderd terug. pipefail zorgt dat een fout in de rewrite niet
  -- door de tweede stap gemaskeerd wordt.
  local rewrite_cmd = { "bash", "-c",
    "set -o pipefail; " .. vim.fn.shellescape(aitext)
      .. " journalistiek_schrijven | " .. vim.fn.shellescape(kampen_fix) }
  ai_system(rewrite_cmd, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("AI rewrite mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return
      end

      local new_lines = vim.split(result.stdout, "\n", { plain = true })
      local output_media
      new_lines, output_media = extract_media_controls(new_lines)
      local media_controls = {
        photographer = source_media.photographer or output_media.photographer,
        caption = source_media.caption or output_media.caption,
      }

      -- Bij 112-template: herschreven output terugzetten in de templatestructuur.
      if is_112_template then
        -- Eerste niet-lege regel = nieuwe titel (strip eventuele `# ` prefix van AI).
        local new_titel = ""
        local new_body_lines = {}
        local found_titel = false
        local skip_blank = true
        for _, l in ipairs(new_lines) do
          if not found_titel then
            local t = vim.trim(l):gsub("^#+%s*", "")
            t = t:gsub("^112:%s*", ""):gsub("^112%s+[^:]+:%s*", "")
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
          is_112_template.prefix .. " " .. new_titel,
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
      local current_fm, current_ctrl, _, current_sections, current_boundary =
        split_article_parts(current_lines)
      local final_fm = #current_fm > 0 and current_fm or saved_fm
      local final_ctrl = #current_ctrl > 0 and current_ctrl or saved_ctrl
      final_ctrl = add_media_controls(final_ctrl, media_controls)
      local final_sections = #current_sections > 0 and current_sections or saved_sections
      local rewritten_body_str = table.concat(new_lines, "\n")
      new_lines = reassemble_article(
        final_fm,
        final_ctrl,
        new_lines,
        final_sections,
        current_boundary or saved_boundary
      )

      local rewritten_str = table.concat(new_lines, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      vim.b[buf].cached_metadata = nil
      vim.b[buf].cached_calendar_metadata = nil
      vim.b[buf].cached_facebook_text = nil

      -- Vul de e:-regel met de kranten (dateline) + suggesties (plaatsenscan),
      -- zodat je vóór <leader>aw ziet en kunt bijsturen waar het heen gaat.
      fill_editions_line(buf, rewritten_str)

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

      if needs_calendar then
        -- articlemeta --calendar levert gewone metadata én kalenderdata. De
        -- losse metadata-call daarnaast was volledig dubbel werk.
        ai_system({ articlemeta, "--calendar" }, { text = true, stdin = rewritten_str }, function(cal_result)
          vim.schedule(function()
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
        end, "AI · Kalender", buf)
      else
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
        end, "AI · Metadata", buf)
      end

      if needs_facebook then
        local fb_prompt = _112_signal_score(rewritten_body_str) >= _112_THRESHOLD and "facebook_bericht_112" or "facebook_bericht"
        ai_system({ aitext, fb_prompt }, { text = true, stdin = rewritten_body_str }, function(fb_result)
          vim.schedule(function()
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
        end, "AI · Facebook", buf)
      end

      -- Auto-detect kalenderberichten als er geen expliciete calendar: x aanwezig is.
      -- Sla over als er al een ## Kalender-sectie is (behouden via trailing_sections
      -- hierboven) — anders draait elke <leader>ar de kalender-AI onnodig opnieuw.
      local already_has_calendar_section = rewritten_str:find("\n## Kalender", 1, true) ~= nil
        or rewritten_str:match("^## Kalender") ~= nil
      -- calendar_ai_started: de import-detectie (BufReadPost) kan de kalender-AI
      -- al gestart hebben; dan niet nog eens draaien bij het herschrijven.
      if not needs_calendar and not already_has_calendar_section
         and not vim.b[buf].calendar_ai_started then
        local cal_score = _calendar_signal_score(rewritten_body_str)
        if cal_score >= _CALENDAR_THRESHOLD then
          vim.notify(
            string.format("Kalenderdetectie (score %d) — kalendermetadata wordt opgehaald.", cal_score),
            vim.log.levels.INFO
          )
          _run_articlemeta_calendar(buf)
        end
      end

      -- Als dit nog geen 112-templateartikel was maar de rewritten tekst wél
      -- als 112 scoort: opnieuw aanbieden als importdetectie dit niet al aan
      -- de gebruiker heeft gevraagd. Een eerder expliciet "Nee" blijft staan.
      if not is_112_template then
        local already_112 = false
        for _, line in ipairs(final_ctrl) do
          local k, v = line:match("^(%a[%a%d_]*)%s*:%s*(.-)%s*$")
          if k and v and k:lower() == "rubriek" and v:lower() == "112" then
            already_112 = true; break
          end
        end
        local score = _112_signal_score(rewritten_body_str)
        if not already_112 and score >= _112_THRESHOLD then
          _offer_112_template(buf, score, "na herschrijven")
        end
      end
    end)
  end, "AI · Herschrijven", buf)
end

function M.visual_rewrite()
  run_on_visual_selection("journalistiek_schrijven", false)
end

vim.keymap.set("n", "<leader>ar", M.rewrite_article_buffer, {
  desc = "Artikel herschrijven naar krantenstijl",
})

vim.keymap.set("v", "<leader>ai", M.visual_rewrite, {
  desc = "Selectie direct herschrijven naar krantenstijl",
})

-- Read calendar fields from YAML frontmatter lines.
local function extract_calendar_frontmatter(lines)
  local fields = {}
  local in_fm = false
  local in_calendar = false
  local dash_count = 0
  local list_key = nil

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
          local key, val = line:match("^  ([%w_]+):%s*(.*)$")
          if key then
            list_key = nil
            if key == "recurrence_days" and val == "" then
              fields[key] = {}
              list_key = key
            elseif val ~= "" and val ~= "null" and val ~= "~" then
              -- strip surrounding quotes that YAML may have added
              fields[key] = val:gsub("^[\"']", ""):gsub("[\"']$", "")
            end
          else
            local list_val = line:match("^  %- (.+)%s*$")
            if list_val and list_key and type(fields[list_key]) == "table" then
              local clean = list_val:gsub("^[\"']", ""):gsub("[\"']$", "")
              table.insert(fields[list_key], clean)
            end
          end
        end
      end
    end
  end
  return fields
end

local function yaml_scalar(val)
  if not val or val == "" or val == "null" or val == "~" then return nil end
  return val:gsub("^[\"']", ""):gsub("[\"']$", "")
end

-- Meervoudige kalenderdata gebruikt calendar.items. We lezen alleen de
-- redactierelevante scalars; Pubble-ID's blijven uitsluitend in frontmatter.
local function extract_calendar_items(lines)
  local items = {}
  local in_fm = false
  local in_calendar = false
  local in_items = false
  local dash_count = 0
  local current = nil
  local list_key = nil

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
        elseif line:match("^  items:%s*$") then
          in_items = true
        elseif in_items then
          local item_key = line:match("^  %- item_key:%s*(.+)%s*$")
          if item_key then
            current = { item_key = yaml_scalar(item_key) }
            table.insert(items, current)
            list_key = nil
          elseif current then
            local key, val = line:match("^    ([%w_]+):%s*(.*)$")
            if key then
              list_key = nil
              if key == "recurrence_days" or (val == "" and key == "missing_event_fields") then
                current[key] = {}
                list_key = key
              else
                local scalar = yaml_scalar(val)
                if scalar then current[key] = scalar end
              end
            else
              local list_val = line:match("^    %- (.+)%s*$")
              if list_val and list_key and type(current[list_key]) == "table" then
                local scalar = yaml_scalar(list_val)
                if scalar then table.insert(current[list_key], scalar) end
              end
            end
          end
        end
      end
    end
  end
  return items
end

-- Build lines for the ## Kalender review section from frontmatter fields.
local function build_calendar_section_lines(lines)
  local f = extract_calendar_frontmatter(lines)
  local items = extract_calendar_items(lines)
  local is_multiple = f.mode == "multiple" or #items > 0
  if not is_multiple and f.calendar_ready ~= "true" then return nil end
  if is_multiple and #items == 0 then return nil end

  local section = { "", "---", "", "## Kalender", "" }
  local function add(target, label, val)
    if val and val ~= "" then
      table.insert(target, label .. ": " .. val)
    end
  end

  local function add_item(target, item)
    add(target, "Titel",       item.calendar_title or item.event_title)
    add(target, "Datum",       item.event_date)
    add(target, "Einddatum",   item.event_end_date)
    add(target, "Herhaling",   item.recurrence)
    if type(item.recurrence_days) == "table" and #item.recurrence_days > 0 then
      add(target, "Dagen", table.concat(item.recurrence_days, ", "))
    end
    add(target, "Herhaal tot", item.recurrence_until)
    add(target, "Tijd",        item.start_time)
    add(target, "Eindtijd",    item.end_time)
    add(target, "Locatie",     item.location_name)
    add(target, "Adres",       item.location_address)
    add(target, "Stad",        item.city)

    if item.calendar_body and item.calendar_body ~= "" then
      table.insert(target, "")
      table.insert(target, item.calendar_body)
    end
    if item.calendar_ready ~= "true" and item.missing_event_fields then
      local missing = item.missing_event_fields
      if type(missing) == "table" then missing = table.concat(missing, ", ") end
      table.insert(target, "")
      table.insert(target, "<!-- Ontbreekt: " .. missing .. " -->")
    end
  end

  if is_multiple then
    for index, item in ipairs(items) do
      local title = item.calendar_title or item.event_title or ("Agenda-item " .. index)
      table.insert(section, "### " .. index .. ". " .. title)
      table.insert(section, "<!-- calendar-key: " .. (item.item_key or ("event-" .. index)) .. " -->")
      table.insert(section, "")
      add_item(section, item)
      if index < #items then table.insert(section, "") end
    end
    return section
  end

  add_item(section, f)

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
function _run_articlemeta_calendar(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) and vim.b[buf].calendar_ai_running then
    vim.notify("Kalenderanalyse loopt al voor dit artikel.", vim.log.levels.INFO)
    return
  end

  -- Markeer dat de kalender-AI voor deze buffer is gestart, zodat de
  -- automatische detectie (import én rewrite) hem niet twee keer draait.
  -- calendar_ai_running voorkomt tegelijk een tweede handmatige start; na
  -- voltooiing mag <leader>ac bewust opnieuw genereren.
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.b[buf].calendar_ai_started = true
    vim.b[buf].calendar_ai_running = true
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")

  ai_system({ articlemeta, "--calendar" }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.b[buf].calendar_ai_running = false
      end
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
        -- Een eventuele handmatige "cal: x"/"calendar: x" controleregel is nu
        -- overbodig (de kalenderdata staat al in de buffer) — anders blijft hij
        -- staan en laat pubble-send de kalender-AI bij <leader>aw ten onrechte
        -- opnieuw draaien.
        strip_leading_control_line(buf, "^[Cc]al[^:]*:%s*x%s*$")
        vim.notify("Kalenderdata toegevoegd. Controleer en pas aan, dan <leader>aw.", vim.log.levels.INFO)
      else
        vim.notify("Geen kalenderitem gedetecteerd in de tekst.", vim.log.levels.WARN)
      end
    end)
  end, "AI · Kalender", buf)
end

function M.articlemeta_calendar_buffer()
  _run_articlemeta_calendar(vim.api.nvim_get_current_buf())
end

-- Kalenderdetectie bij import: vuurt op BufReadPost voor Desktop-bestanden.
-- Eénmalig per buffer (flag voorkomt herhaling bij latere saves).
local function _calendar_autodetect(buf)
  if vim.b[buf].calendar_autodetect_done then return end
  vim.b[buf].calendar_autodetect_done = true
  if vim.b[buf].calendar_ai_running then return end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  local text = table.concat(lines, "\n")

  -- Sla over als er al een ## Kalender-blok in de buffer staat: de
  -- kalenderdata bestaat dan al (bijv. een reeds gemaakt artikel dat opnieuw
  -- verstuurd wordt). Opnieuw de AI draaien zou dat blok overschrijven.
  -- Handmatig hergenereren kan altijd nog via <leader>ac.
  if text:find("\n## Kalender", 1, true) or text:match("^## Kalender") then
    return
  end

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

-- Eén gedeelde bevestigingsroute voor import en post-rewrite-detectie.
-- `Nee` is een expliciete bufferbeslissing en mag later in dezelfde workflow
-- niet door een tweede detector worden genegeerd.
_offer_112_template = function(buf, score, context)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf]._112_rejected or vim.b[buf]._112_prompt_pending then return end

  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if text:find("rubriek:%s*112") then return end
  if text:find("^112:") or text:find("^112%s+[^:]+:") then return end

  vim.b[buf]._112_prompt_pending = true
  local suffix = context and (" — " .. context) or ""
  vim.ui.select({ "Ja", "Nee" }, {
    prompt = string.format("112-bericht behandelen? (score %d)%s", score, suffix),
  }, function(choice)
    vim.b[buf]._112_prompt_pending = false
    if choice == "Nee" then
      vim.b[buf]._112_rejected = true
      vim.notify("112-detectie afgewezen voor dit artikel.", vim.log.levels.INFO)
      return
    end
    if choice ~= "Ja" then return end
    vim.b[buf]._112_rejected = false
    require("krant").apply_template_by_name("112 nieuws", {}, buf)
  end)
end

local function _112_autodetect(buf)
  if vim.b[buf]._112_autodetect_done then return end
  vim.b[buf]._112_autodetect_done = true
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  local text = table.concat(lines, "\n")
  -- Sla over als al als 112 gemarkeerd of al in templatevorm.
  if text:find("rubriek:%s*112") then return end
  if text:find("^112:") or text:find("^112%s+[^:]+:") then return end
  local score = _112_signal_score(text)
  if score < _112_THRESHOLD then return end
  _offer_112_template(buf, score, "bij import")
end

-- Alleen als inspecteerbare testpunten exporteren; productie gebruikt de
-- lokale functies en blijft daardoor ongevoelig voor een oude moduletabel.
M._112_autodetect = _112_autodetect
M._offer_112_template = _offer_112_template

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function(ev)
    vim.schedule(function() _112_autodetect(ev.buf) end)
  end,
})

vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Kalendergegevens maken en ter controle tonen",
})

-- Lokale upvalue voor de eventvoorbereiding. De verzendflow gebruikt bewust
-- niet M._event_prepare: bij het opnieuw sourcen van deze module kan een oude
-- moduletabel nog in een callback leven. De lokale closure blijft na volledige
-- moduleload aan precies de bijbehorende implementatie gekoppeld.
local event_prepare

function M.pubble_send(target_buf)
  local buf = target_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf].publication_in_progress then
    vim.notify("Deze publicatierun is al bezig.", vim.log.levels.INFO)
    return
  end

  -- AI-opmaak draait NIET automatisch — ook niet voor columns/raadspraat/
  -- ondernemen. Wie wil: <leader>ao (tekstcheck) en/of <leader>at
  -- (tussenkopjes + streamer) handmatig vóór <leader>aw.

  -- Eén verzendverzoek blijft staan tot álle bufferwijzigende AI-taken klaar
  -- zijn. De laatste taak start de verzending exact één keer; geen polling.
  if (vim.b[buf].pending_jobs or 0) > 0 then
    if not vim.b[buf].send_requested then
      vim.b[buf].send_requested = true
      vim.notify("Verzenden start automatisch zodra de achtergrondtaken klaar zijn.", vim.log.levels.INFO)
    end
    return
  end

  -- Eénmalige keuze uit de agenda-waarschuwing. De buffer zelf blijft intact;
  -- alleen het tijdelijke Pubble-bestand wordt zonder kalenderdata verwerkt.
  local skip_calendar = vim.b[buf].skip_calendar_once == true
  vim.b[buf].skip_calendar_once = nil

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
  -- De editie zelf wordt NIET hier bepaald maar door
  -- `pubble-send --resolve-editions` (zie verderop): pubble-send is de enige
  -- bron van waarheid voor waar het artikel heengaat, zodat de datumdialoog
  -- gegarandeerd over dezelfde edities loopt als de daadwerkelijke verzending.
  local editie = nil
  local resolved_editions = {}
  local editie_namen = {
    B = "De Brug", SW = "De Swollenaer", ST = "De Stadskoerier",
    Z = "Zeewolde Actueel", D = "De Drontenaar", K = "Nieuwsbode de Kop",
  }
  local has_calendar = false
  local has_facebook = false
  for _, line in ipairs(lines) do
    if line:match("^## Kalender") then has_calendar = true end
    if line:match("^## Facebook") then has_facebook = true end
  end
  if skip_calendar then has_calendar = false end

  -- Write the temp file inside Pubble Inbox so pubble-media can find photos
  -- in the same dropzone folder when --write-ids triggers the media upload.
  -- Use the original file's stem so photos get renamed to match in used/.
  local inbox = require('texttools_paths').inbox()
  local stem = (file_path ~= "") and vim.fn.fnamemodify(file_path, ":t:r") or ("verzenden-" .. os.time())
  local resume_file = vim.b[buf].failed_send_file
  local temp_file
  if resume_file and vim.fn.filereadable(resume_file) == 1 then
    temp_file = resume_file
  else
    resume_file = nil
    vim.b[buf].failed_send_file = nil
    temp_file = inbox .. "/" .. stem .. ".md"
    -- Vermijd alleen bestanden die niet bij deze hervatflow horen.
    local tc = 1
    while vim.fn.filereadable(temp_file) == 1 do
      temp_file = inbox .. "/" .. stem .. "-" .. tc .. ".md"
      tc = tc + 1
    end
  end
  local function discard_unpublished_temp()
    -- Een herstelbestand kan al Pubble-ID's bevatten en mag ook bij annuleren
    -- of een lokale validatiefout nooit worden weggegooid.
    if not resume_file then vim.fn.delete(temp_file) end
  end
  local function file_has_event_sections()
    if vim.fn.filereadable(temp_file) ~= 1 then return false end
    for _, line in ipairs(vim.fn.readfile(temp_file)) do
      if line:match("^## Korte versie") or line:match("^## Dagreminder") then
        return true
      end
    end
    return false
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

  local _do_pubble_send

  -- Zet het webartikel expliciet als ongepubliceerd concept klaar. De control
  -- line staat boven de vaste artikelgrens, zodat pubble-send hem valideert,
  -- naar web.draft omzet en nooit als artikeltekst publiceert.
  local function mark_web_unpublished()
    local current = vim.fn.readfile(temp_file)
    local boundary_index = nil
    for i, line in ipairs(current) do
      local trimmed = vim.trim(line)
      if trimmed:lower():match("^web:%s*draft%s*$") then
        return true
      end
      if trimmed == ARTICLE_BOUNDARY then
        boundary_index = i
        break
      end
    end
    if not boundary_index then
      return false
    end
    table.insert(current, boundary_index, "web: draft")
    vim.fn.writefile(current, temp_file)
    return true
  end

  local function send_unpublished()
    if not mark_web_unpublished() then
      discard_unpublished_temp()
      vim.notify("Ongepubliceerd plaatsen mislukt: artikelgrens ontbreekt.", vim.log.levels.ERROR)
      return
    end
    -- Een concept heeft geen publicatiedatum en mag geen toekomstige
    -- vervolgpublicaties voorbereiden. Het hoofdartikel en de agenda-items
    -- worden door pubble-send wel als inactieve concepten aangemaakt.
    _do_pubble_send({}, true, true)
  end

  -- Bouw pubble-send-aanroep en voer hem uit (na eventuele planningsdialoog).
  _do_pubble_send = function(
    display_dates,
    event_preparation_complete,
    suppress_event_followups
  )
    vim.b[buf].publication_in_progress = true
    local cmd = {
      pubble_send,
      temp_file,
      "--create",
      "--no-open",
      "--write-ids",
      "--require-article-boundary",
    }
    if skip_calendar then table.insert(cmd, "--without-calendar") end
    if next(display_dates) ~= nil then
      table.insert(cmd, "--display-dates")
      table.insert(cmd, vim.fn.json_encode(display_dates))
    end
    local function handle_send_result(result, event_checked, event_report)
      vim.schedule(function()
        -- Bij een fout bevat dit bestand mogelijk al nieuwe Pubble-ID's. Laad
        -- die duurzame herstelstate terug in de buffer en hergebruik exact dit
        -- bestand bij de volgende <leader>aw; verwijderen zou duplicaten riskeren.
        if result.code ~= 0 then
          if vim.fn.filereadable(temp_file) == 1 then
            local recovered = vim.fn.readfile(temp_file)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, recovered)
            vim.b[buf].failed_send_file = temp_file
          end
        end

        -- Vervolgplaatsingen worden pas na de volledig geslaagde hoofdflow
        -- aangemaakt: dan bestaan articleJoinId, web-URL en media-ID. Pubble
        -- opent en het archief verhuist pas nadat ook deze stap klaar is.
        if result.code == 0 and not event_checked then
          if suppress_event_followups or not file_has_event_sections() then
            handle_send_result(result, true, nil)
            return
          end
          ai_system(
            { pubble_event, "plaats", temp_file, "--json" },
            { text = true },
            function(event_result)
              vim.schedule(function()
                local event_ok, event_data = pcall(
                  vim.fn.json_decode, event_result.stdout or ""
                )
                if event_result.code ~= 0 or not event_ok or type(event_data) ~= "table" then
                  vim.b[buf].publication_in_progress = false
                  vim.b[buf].failed_send_file = temp_file
                  if vim.fn.filereadable(temp_file) == 1 then
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(temp_file))
                  end
                  local err = vim.trim(event_result.stderr or event_result.stdout or "")
                  vim.notify(
                    "Hoofdartikel is geplaatst, maar vervolgplaatsingen zijn niet compleet"
                      .. (err ~= "" and (": " .. err) or "")
                      .. ". <leader>aw hervat zonder dubbele artikelen.",
                    vim.log.levels.ERROR
                  )
                  return
                end
                handle_send_result(result, true, event_data)
              end)
            end,
            "Pubble · Evenementvervolgen"
          )
          return
        end

        if result.code == 0 then
          -- Strip eventueel achtergebleven control lines uit de originele buffer.
          strip_leading_control_line(buf, "^[Cc]al[^:]*:%s*x%s*$")
          strip_leading_control_line(buf, "^[Ff]acebook%s*:%s*x%s*$")

          local output = vim.trim(result.stdout or "")
          local article_url = output:match("Pubble article: (https://[^\n]+)")

          local verzonden = {}
          for token in (editie or "B"):gmatch("[^,]+") do
            local code = vim.trim(token)
            table.insert(verzonden, editie_namen[code] or code)
          end
          local msg = "Verzonden naar: " .. table.concat(verzonden, " + ") .. " (krant + website)"
          if has_calendar then msg = msg .. " | kalender" end
          if has_facebook then msg = msg .. " | Facebook" end
          if event_report then
            local event_count = #(event_report.geplaatst or {})
            local existing_count = #(event_report.overgeslagen or {})
            msg = msg .. " | " .. event_count .. " vervolgplaatsing(en)"
            if existing_count > 0 then msg = msg .. " (" .. existing_count .. " hervat)" end
          end
          notify_workflow(msg)

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

            -- Met de nieuwe structuur is alles boven de marker workflowdata.
            -- Exporteer alleen het artikel. Oude buffers zonder marker blijven
            -- via de historische regel-voor-regelopschoning werken.
            for i, line in ipairs(export_lines) do
              if vim.trim(line) == ARTICLE_BOUNDARY then
                local article_only = {}
                for j = i + 1, #export_lines do table.insert(article_only, export_lines[j]) end
                export_lines = article_only
                break
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
                -- >-streamer: tekst naar de header, regel uit de body.
                local q = trimmed:match("^>%s*(.+)$")
                if q and not streamer_text then streamer_text = q end
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

          -- Verplaats pas na hoofd- én vervolgpublicatie het volledige
          -- statusbestand naar het operationele publicatiearchief.
          local archive_result = vim.system(
            { texttools_python, "-m", "texttools.pubble_archive", temp_file, "--json" },
            { text = true }
          ):wait()
          local archive_ok, archive_data = pcall(vim.fn.json_decode, archive_result.stdout or "")
          if archive_result.code ~= 0 or not archive_ok or type(archive_data) ~= "table"
              or type(archive_data.path) ~= "string" then
            vim.b[buf].publication_in_progress = false
            vim.b[buf].failed_send_file = temp_file
            if vim.fn.filereadable(temp_file) == 1 then
              vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(temp_file))
            end
            local archive_err = vim.trim(archive_result.stderr or archive_result.stdout or "")
            vim.notify(
              "Artikel is gepubliceerd, maar archiveren mislukte"
                .. (archive_err ~= "" and (": " .. archive_err) or "")
                .. ". Bron en tempbestand zijn behouden.",
              vim.log.levels.ERROR
            )
            return
          end
          temp_file = archive_data.path
          vim.b[buf].failed_send_file = nil
          vim.b[buf].event_review_state = nil

          -- Het browsermoment is het eindsignaal: hoofdartikel, media,
          -- eventuele vervolgen en archivering zijn nu allemaal gereed.
          if article_url then
            open_url_without_focus(article_url)
          end

          -- Verwijder origineel op bureaublad; buffer blijft zichtbaar voor nacontrole.
          if file_path ~= "" and vim.fn.filereadable(file_path) == 1 then
            vim.fn.delete(file_path)
          end

          -- Zet bovenaan de (nog open) buffer wanneer verzonden is, zodat je bij
          -- meerdere open buffers in één oogopslag ziet wat al gelukt is. De
          -- artikel-URL komt eronder: klikbaar met gx en meteen de weg terug.
          -- Opnieuw verzenden vervangt het bestaande blok i.p.v. te stapelen.
          local sent_marker = "**Verstuurd naar Pubble op " .. os.date("%d-%m-%Y %H:%M") .. "**"
          local marker_block = { sent_marker }
          if article_url then table.insert(marker_block, article_url) end

          local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
          if buf_lines[1] and buf_lines[1]:match("^%*%*Verstuurd naar Pubble op ") then
            -- Vervang het bestaande blok (marker + evt. eerdere URL-regel).
            local replace_to = 1
            if buf_lines[2] and buf_lines[2]:match("^https?://") then replace_to = 2 end
            vim.api.nvim_buf_set_lines(buf, 0, replace_to, false, marker_block)
          else
            local prepend = {}
            for _, l in ipairs(marker_block) do table.insert(prepend, l) end
            table.insert(prepend, "")
            vim.api.nvim_buf_set_lines(buf, 0, 0, false, prepend)
          end

          vim.b[buf].publication_in_progress = false

        else
          vim.b[buf].publication_in_progress = false
          local output = vim.trim(result.stderr or result.stdout or "")
          vim.notify(output ~= "" and output or "Pubble send mislukt", vim.log.levels.ERROR)
        end
      end)
    end

    local function run_main_send()
      ai_system(cmd, { text = true }, function(result)
        handle_send_result(result, false, nil)
      end, "Pubble · Verzenden")
    end

    -- Bij een hervatbestand staan de secties al klaar; stel de vragen dan
    -- niet opnieuw. In een verse flow worden alle keuzes en AI-teksten eerst
    -- voorbereid, dus vóór de eerste Pubble-write.
    if event_preparation_complete or file_has_event_sections() then
      run_main_send()
      return
    end
    -- Vervolgpublicaties bestaan uitsluitend voor een expliciete, zichtbare
    -- ## Kalender-sectie. Gewone artikelen starten dus geen overbodige
    -- pubble-event-subprocess en gaan meteen door naar de hoofdpublicatie.
    if not has_calendar then
      run_main_send()
      return
    end
    event_prepare(
      buf,
      temp_file,
      display_dates,
      resolved_editions,
      function(ok, err, prepared)
        if not ok then
          vim.b[buf].publication_in_progress = false
          discard_unpublished_temp()
          if err == AI_CANCELLED then
            vim.notify("Genereren van evenementvervolgteksten geannuleerd.", vim.log.levels.INFO)
          else
            vim.notify(err or "Evenementvoorbereiding mislukt", vim.log.levels.ERROR)
          end
          return
        end
        if prepared then
          vim.b[buf].publication_in_progress = false
          vim.b[buf].event_review_state = {
            display_dates = display_dates,
            editions = resolved_editions,
          }
          discard_unpublished_temp()
          notify_workflow(
            "Controleer of bewerk de vervolgteksten; druk daarna opnieuw <leader>aw om alles samen te publiceren."
          )
          return
        end
        run_main_send()
      end
    )
  end

  -- Na de eerste eventvoorbereiding is de zichtbare buffer de reviewbron.
  -- De tweede <leader>aw maakt daar een vers tempbestand van en hergebruikt de
  -- eerder gekozen datums; alle Pubble-writes gebeuren pas vanaf dit punt.
  local review_state = vim.b[buf].event_review_state
  if type(review_state) == "table" then
    resolved_editions = review_state.editions or {}
    editie = table.concat(resolved_editions, ", ")
    _do_pubble_send(review_state.display_dates or {}, true)
    return
  end

  -- 112-berichten altijd direct plaatsen — geen planningsdialoog nodig.
  local is_112 = false
  for _, line in ipairs(pubble_lines) do
    if line:match("^112:") or line:match("^112%s+[^:]+:") then
      is_112 = true
      break
    end
  end

  -- Vraag pubble-send waar dit artikel heengaat (expliciete e:/editions →
  -- dateline → default De Brug). Dit is dezelfde logica als de echte
  -- verzending, dus dialoog en verzending kunnen nooit meer uiteenlopen.
  local resolve_cmd = {
    pubble_send,
    temp_file,
    "--resolve-editions",
    "--require-article-boundary",
  }
  if skip_calendar then table.insert(resolve_cmd, "--without-calendar") end
  vim.system(
    resolve_cmd,
    { text = true },
    function(resolve_result)
    vim.schedule(function()
      local rok, resolved = pcall(vim.fn.json_decode, resolve_result.stdout or "")
      if resolve_result.code ~= 0 or not rok or type(resolved) ~= "table" or type(resolved.editions) ~= "table" then
        local err = vim.trim(resolve_result.stderr or "")
        discard_unpublished_temp()
        vim.notify(
          "Editie bepalen mislukt" .. (err ~= "" and (": " .. err) or "") .. " — verzending afgebroken.",
          vim.log.levels.ERROR
        )
        return
      end

      local calendar_missing = {}
      if type(resolved.calendar_missing) == "table" then
        for _, field in ipairs(resolved.calendar_missing) do
          if type(field) == "string" then table.insert(calendar_missing, field) end
        end
      end
      if #calendar_missing > 0 and not skip_calendar then
        discard_unpublished_temp()
        local missing_label = table.concat(calendar_missing, ", ")
        local publish_without = "Web en print toch plaatsen"
        local complete_article = "Bericht aanvullen"
        vim.ui.select({ publish_without, complete_article }, {
          prompt = "Agenda-item niet geplaatst — ontbreekt: " .. missing_label .. ". Wat wil je doen?",
        }, function(choice)
          if choice == publish_without then
            vim.b[buf].skip_calendar_once = true
            M.pubble_send(buf)
          elseif choice == complete_article then
            vim.notify(
              "Vul de ontbrekende gegevens aan onder ## Kalender en druk daarna opnieuw <leader>aw.",
              vim.log.levels.INFO
            )
          else
            vim.notify("Verzending geannuleerd.", vim.log.levels.INFO)
          end
        end)
        return
      end

      editie = table.concat(resolved.editions, ", ")
      resolved_editions = resolved.editions
      local bestemming = {}
      for i, code in ipairs(resolved.editions) do
        if resolved.names and resolved.names[i] then editie_namen[code] = resolved.names[i] end
        table.insert(bestemming, editie_namen[code] or code)
      end
      -- Bij meerdere edities toont het aansluitende planningsmenu alle kranten
      -- en datums al; een extra melding onderaan is dan alleen een tussenstap.
      -- Voor één editie blijft de korte bestemmingsbevestiging wel nuttig.
      if resolved.source and resolved.source:match("^standaard") then
        -- Geen dateline herkend → stille terugval naar De Brug. Als
        -- waarschuwing tonen zodat een verkeerde bestemming opvalt vóór het
        -- versturen (dit is de misser die je met annuleren opving).
        vim.notify(
          "LET OP: geen dateline herkend — gaat standaard naar De Brug. Voeg e: toe als dat niet klopt.",
          vim.log.levels.WARN
        )
      elseif #resolved.editions == 1 then
        local msg = "Artikel gaat naar: " .. table.concat(bestemming, " + ")
        if resolved.source then
          msg = msg .. "  (" .. resolved.source .. ")"
        end
        if #msg > vim.o.columns - 1 then
          msg = msg:sub(1, math.max(1, vim.o.columns - 2)) .. "…"
        end
        vim.notify(msg, vim.log.levels.INFO)
      end

      if is_112 then
        _do_pubble_send({})
        return
      end

      -- Haal planningsuggesties op en toon per editie een keuze.
      -- Bij fout in pubble-schedule: toon alsnog een minimale dialog per editie.
      -- Geef het tijdelijke artikel mee: pubble-schedule gebruikt
      -- calendar.event_date als uiterste aanbevelingsdatum voor events.
      vim.system({ pubble_schedule, editie, "--article", temp_file }, { text = true }, function(sched_result)
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

      -- Edities in de volgorde van resolve: primaire krant eerst.
      local edition_codes = {}
      for _, code in ipairs(resolved.editions) do table.insert(edition_codes, code) end

      -- Voeg N dagen toe aan een YYYY-MM-DD datum string.
      local function date_add_days(date_str, n)
        local y, m, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
        if not y then return date_str end
        local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        local t2 = t + n * 86400
        return os.date("%Y-%m-%d", t2)
      end

      -- vim.fn.json_decode zet JSON-null om in de truthy userdata vim.NIL.
      -- Normaliseer optionele planningsvelden vóór vergelijkingen/indexering.
      local function optional_string(value)
        return type(value) == "string" and value or nil
      end

      local function optional_table(value)
        return type(value) == "table" and value or {}
      end

      local function schedule_info(code)
        local value = has_data and sched_data[code] or nil
        return type(value) == "table" and value or nil
      end

      -- Bouw een lijst van 7 opeenvolgende dagen (als items + values),
      -- markeer de aanbevolen dag en krantendata.
      local function build_week_items(info, week_offset)
        local items = {}
        local item_values = {}
        local counts = optional_table(info and info.counts)
        local suggested = optional_string(info and info.suggested)
        local latest_date = optional_string(info and info.latest_date)
        local pub_dates = optional_table(info and info.publication_dates)
        -- Sla krantendatums op in een set voor snelle lookup.
        local krant_set = {}
        for _, pd in ipairs(pub_dates) do
          if type(pd) == "string" then krant_set[pd] = true end
        end

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
          if latest_date and d > latest_date then
            label = label .. "  (na evenement)"
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
        local info = schedule_info(code)

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
          table.insert(items, "Ongepubliceerd plaatsen")
          table.insert(item_values, "__unpublished__")

          local week_nr = tonumber(os.date("%V", base + 3 * 86400))  -- donderdag bepaalt ISO-weeknummer
          local krant_naam = editie_namen[code] or code
          local volgnr = #edition_codes > 1 and ("  [" .. idx .. "/" .. #edition_codes .. "]") or ""
          vim.ui.select(items, {
            prompt = krant_naam .. volgnr .. "  —  week " .. week_nr .. ":",
          }, function(choice, choice_idx)
            if choice == nil then
              discard_unpublished_temp()
              vim.notify("Verzending geannuleerd.", vim.log.levels.INFO)
              return
            end
            local value = choice_idx and item_values[choice_idx] or "direct"
            if value == "__next__" then
              show_week(week_offset + 1)
            elseif value == "__prev__" then
              show_week(week_offset - 1)
            elseif value == "__unpublished__" then
              send_unpublished()
            else
              display_dates[code] = value
              ask_edition(idx + 1)
            end
          end)
        end

        show_week(0)
      end

      -- De gewone route hoeft niet langer één verplicht menu per editie te
      -- tonen. Bouw eerst alle aanbevelingen en laat ze in één handeling
      -- accepteren; alleen "Datums aanpassen" opent de bestaande detailmenu's.
      local recommended = {}
      local summary = {}
      local all_recommended = has_data
      for _, code in ipairs(edition_codes) do
        local info = schedule_info(code)
        local suggested = optional_string(info and info.suggested)
        local latest_date = optional_string(info and info.latest_date)
        if not suggested then
          all_recommended = false
          if latest_date then
            vim.notify(
              string.format(
                "Geen aanbevolen datum voor %s uiterlijk %s; kies handmatig.",
                code,
                latest_date
              ),
              vim.log.levels.WARN
            )
          end
        else
          local is_krant = false
          for _, publication_date in ipairs(optional_table(info and info.publication_dates)) do
            if publication_date == suggested then is_krant = true; break end
          end
          local count = optional_table(info and info.counts)[suggested] or 0
          recommended[code] = suggested .. ":" .. (is_krant and "krant" or tostring(count))
          local date_label = suggested == os.date("%Y-%m-%d")
              and "vandaag"
              or (suggested:sub(9, 10) .. "-" .. suggested:sub(6, 7))
          table.insert(summary, code .. " " .. date_label)
        end
      end

      if not all_recommended then
        ask_edition(1)
        return
      end

      local accept_label = #edition_codes == 1 and "Aanbevolen datum accepteren" or "Aanbevolen datums accepteren"
      local adjust_label = #edition_codes == 1 and "Datum aanpassen" or "Datums per editie aanpassen"
      local unpublished_label = "Ongepubliceerd plaatsen"
      vim.ui.select({
        accept_label,
        adjust_label,
        "Direct plaatsen",
        unpublished_label,
      }, {
        prompt = "Publicatieplanning — " .. table.concat(summary, ", ") .. ":",
      }, function(choice)
        if choice == nil then
          discard_unpublished_temp()
          vim.notify("Verzending geannuleerd.", vim.log.levels.INFO)
        elseif choice == accept_label then
          _do_pubble_send(recommended)
        elseif choice == adjust_label then
          ask_edition(1)
        elseif choice == unpublished_label then
          send_unpublished()
        else
          _do_pubble_send({})
        end
      end)
    end)
      end)
    end)
    end
  )
end



vim.api.nvim_create_user_command("PubbleSend", M.pubble_send, {
  desc = "Artikel naar Pubble verzenden",
  force = true,
})

vim.keymap.set("n", "<leader>aw", M.pubble_send, {
  desc = "Artikel naar Pubble verzenden",
})

-- ---------------------------------------------------------------------------
-- Evenement-vervolgplaatsingen: korte versie op T-10 en dagreminder(s).
-- Na planning maar vóór de eerste Pubble-write worden de vragen gesteld en
-- de teksten in de buffer gezet. De tweede <leader>aw gebruikt de beoordeelde
-- buffer: pubble-send maakt hoofdartikel + media en pubble-event de gekoppelde
-- vervolgen. Pas daarna opent Pubble.
-- ---------------------------------------------------------------------------

-- "2026-08-28" → "28-08" (alleen weergave in prompts).
local function korte_datum(iso)
  local m, d = tostring(iso):match("^%d+%-(%d+)%-(%d+)$")
  if not m then return tostring(iso) end
  return d .. "-" .. m
end

event_prepare = function(buf, file, display_dates, edition_codes, done)
  -- Een lege Lua-tabel krijgt bij json_encode standaard de vorm `[]`, maar
  -- pubble-event verwacht voor datums altijd een JSON-object. Dit komt onder
  -- meer voor bij de keuze Direct plaatsen.
  local display_dates_json = "{}"
  if type(display_dates) == "table" and next(display_dates) ~= nil then
    display_dates_json = vim.fn.json_encode(display_dates)
  end
  local prepare_cmd = {
    pubble_event,
    "voorbereiden",
    file,
    "--display-dates",
    display_dates_json,
    "--editions",
    vim.fn.json_encode(edition_codes or {}),
    "--json",
  }
  vim.system(prepare_cmd, { text = true }, function(result)
    vim.schedule(function()
      local ok, opties = pcall(vim.fn.json_decode, result.stdout or "")
      if result.code ~= 0 or not ok or type(opties) ~= "table" then
        local err = vim.trim(result.stderr or result.stdout or "")
        done(false, "Evenementvoorbereiding mislukt" .. (err ~= "" and (": " .. err) or ""))
        return
      end
      if not opties.beschikbaar then
        -- Geen evenement of geen toepasselijke vervolgdatum: gewone send.
        done(true, nil, false)
        return
      end

      -- Twee ja/nee-vragen na elkaar (vim.ui.select kent geen multi-select);
      -- Esc telt als nee.
      local keuzes = { kort = false, reminder = false }

      local function klaar()
        if not keuzes.kort and not keuzes.reminder then
          done(true, nil, false)
          return
        end
        local cmd = { pubble_event, "teksten", file }
        if keuzes.kort then table.insert(cmd, "--kort") end
        if keuzes.reminder then table.insert(cmd, "--reminder") end
        table.insert(cmd, "--opties-json")
        table.insert(cmd, result.stdout)
        ai_system(cmd, { text = true }, function(tekst_result)
          vim.schedule(function()
            if tekst_result.code ~= 0 then
              local err = vim.trim(tekst_result.stderr or "")
              done(false, "Vervolgteksten genereren mislukt" .. (err ~= "" and (": " .. err) or ""))
              return
            end
            local generated = vim.trim(tekst_result.stdout or "")
            if generated == "" then
              done(false, "Vervolgteksten genereren gaf geen tekst terug")
              return
            end

            -- Zet de secties in het voorbereidende tempbestand én in de
            -- zichtbare buffer. Het tempbestand wordt hierna verwijderd; bij
            -- de tweede <leader>aw wordt het opnieuw opgebouwd uit de mogelijk
            -- door de gebruiker bewerkte buffer.
            local file_lines = vim.fn.readfile(file)
            while #file_lines > 0 and vim.trim(file_lines[#file_lines]) == "" do
              table.remove(file_lines)
            end
            table.insert(file_lines, "")
            for _, line in ipairs(vim.split(generated, "\n", { plain = true })) do
              table.insert(file_lines, line)
            end
            vim.fn.writefile(file_lines, file)

            if vim.api.nvim_buf_is_valid(buf) then
              local append = { "" }
              for _, line in ipairs(vim.split(generated, "\n", { plain = true })) do
                table.insert(append, line)
              end
              vim.api.nvim_buf_set_lines(buf, -1, -1, false, append)
            end
            done(true, nil, true)
          end)
        end, "Evenement · Vervolgteksten", buf, function()
          vim.schedule(function() done(false, AI_CANCELLED) end)
        end)
      end

      local function vraag_reminder()
        if not (type(opties.reminder) == "table" and opties.reminder.mogelijk) then
          return klaar()
        end
        local dagen = opties.reminder.dagen or {}
        local omschrijving
        if #dagen <= 1 then
          omschrijving = korte_datum(dagen[1])
        else
          omschrijving = korte_datum(dagen[1]) .. " t/m " .. korte_datum(dagen[#dagen])
            .. " (" .. #dagen .. " dagen)"
        end
        vim.ui.select({ "Ja", "Nee" }, {
          prompt = "Dagreminder(s) op " .. omschrijving .. "?",
        }, function(choice)
          keuzes.reminder = (choice == "Ja")
          klaar()
        end)
      end

      local function vraag_kort()
        if not (type(opties.kort) == "table" and opties.kort.mogelijk) then
          return vraag_reminder()
        end
        vim.ui.select({ "Ja", "Nee" }, {
          prompt = "Korte versie op " .. korte_datum(opties.kort.datum)
            .. " (10 dagen vooraf)?",
        }, function(choice)
          keuzes.kort = (choice == "Ja")
          vraag_reminder()
        end)
      end

      vraag_kort()
    end)
  end)
end

-- Alleen als inspecteerbaar/testbaar modulepunt exporteren; de productieflow
-- hierboven gebruikt de stabiele lokale upvalue.
M._event_prepare = event_prepare

-- ---------------------------------------------------------------------------
-- :TeamsRedactie — beheer van de Teams-meldingen naar eindredacteuren.
-- De bron van waarheid is ~/.texttools/teams_notify.json (geseed en gelezen
-- door pubble-send/pubble_teams.py). Dit menu is puur de UI erop: waarneming
-- uit een lokale lijst kiezen, een nieuwe vervanger bewaren, terugzetten naar
-- de vaste eindredacteur, meldingen per editie uitzetten, of alles aan/uit.
-- ---------------------------------------------------------------------------
local teams_config_dir = vim.env.TEXTTOOLS_LOG_DIR
if type(teams_config_dir) ~= "string" or vim.trim(teams_config_dir) == "" then
  teams_config_dir = vim.fn.expand("~/.texttools")
else
  teams_config_dir = vim.fn.expand(teams_config_dir)
end
local teams_config_file = vim.fs.joinpath(teams_config_dir, "teams_notify.json")

local function teams_read_config()
  if vim.fn.filereadable(teams_config_file) == 0 then
    -- Laat pubble-send het bestand seeden met de standaardbezetting, zodat
    -- de mapping maar op één plek leeft (Python).
    vim.system({ pubble_send, "--teams-config" }, { text = true }):wait()
  end
  local ok, config = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(teams_config_file), "\n"))
  end)
  if not ok or type(config) ~= "table" or type(config.editions) ~= "table" then
    vim.notify("Teams-config onleesbaar: " .. teams_config_file, vim.log.levels.ERROR)
    return nil
  end
  return config
end

local function teams_write_config(config)
  vim.fn.writefile(vim.split(vim.json.encode(config), "\n"), teams_config_file)
end

local function teams_email(value)
  if value == nil or value == vim.NIL then return nil end
  local email = vim.trim(tostring(value))
  if email == "" then return nil end
  return email
end

local function teams_same_email(left, right)
  left = teams_email(left)
  right = teams_email(right)
  if left == nil or right == nil then return left == right end
  return left:lower() == right:lower()
end

local function teams_valid_email(email)
  return email:match("^[^%s@]+@[^%s@]+%.[^%s@]+$") ~= nil
end

-- Bouw de keuzelijst uit lokaal opgeslagen vervangers plus de vaste
-- eindredacteuren van alle edities. Een bestaand configbestand zonder
-- `recipients` werkt daardoor direct, zonder migratiestap.
local function teams_known_recipients(config)
  local recipients = {}
  local by_email = {}

  local function add(name, email)
    email = teams_email(email)
    if not email then return end
    name = vim.trim(tostring(name or ""))
    if name == "" then name = email end
    local key = email:lower()
    local existing = by_email[key]
    if existing then
      if existing.name == existing.email and name ~= email then
        existing.name = name
      end
      return
    end
    local person = { name = name, email = email }
    by_email[key] = person
    table.insert(recipients, person)
  end

  if type(config.recipients) == "table" then
    for _, person in ipairs(config.recipients) do
      if type(person) == "table" then add(person.name, person.email) end
    end
  end

  for _, code in ipairs({ "B", "SW", "ST", "Z", "D", "K" }) do
    local edition = config.editions[code]
    if edition then
      add(edition.name, edition.default_email)
      -- Laat ook een oude, handmatig ingestelde waarnemer zien, zelfs als die
      -- nog niet in de nieuwe recipients-lijst is opgeslagen.
      add(nil, edition.email)
    end
  end

  table.sort(recipients, function(left, right)
    local left_key = (left.name .. "\0" .. left.email):lower()
    local right_key = (right.name .. "\0" .. right.email):lower()
    return left_key < right_key
  end)
  return recipients
end

local function teams_recipient_label(config, email)
  for _, person in ipairs(teams_known_recipients(config)) do
    if teams_same_email(person.email, email) then
      if person.name == person.email then return person.email end
      return string.format("%s <%s>", person.name, person.email)
    end
  end
  return teams_email(email) or "geen melding"
end

local function teams_store_recipient(config, name, email)
  if type(config.recipients) ~= "table" then config.recipients = {} end
  for _, person in ipairs(config.recipients) do
    if type(person) == "table" and teams_same_email(person.email, email) then
      person.name = name
      person.email = email
      return
    end
  end
  table.insert(config.recipients, { name = name, email = email })
end

function M.teams_redactie()
  local config = teams_read_config()
  if not config then return end

  local items = {}
  local aan = config.enabled ~= false
  table.insert(items, {
    kind = "toggle",
    label = aan and "Meldingen: AAN — kies om alles uit te zetten"
                 or "Meldingen: UIT — kies om alles aan te zetten",
  })
  for _, code in ipairs({ "B", "SW", "ST", "Z", "D", "K" }) do
    local e = config.editions[code]
    if e then
      local status
      if e.email == vim.NIL or e.email == nil then
        status = (e.default_email == vim.NIL or e.default_email == nil)
          and "geen melding (standaard)" or "UITGEZET"
      elseif not teams_same_email(e.email, e.default_email) then
        status = "WAARNEMING: " .. teams_recipient_label(config, e.email)
      else
        status = teams_recipient_label(config, e.email)
      end
      table.insert(items, {
        kind = "edition", code = code,
        label = string.format("%-3s %-18s → %s", code, e.krant or code, status),
      })
    end
  end

  vim.ui.select(items, {
    prompt = "Teams-meldingen eindredactie:",
    format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end

    if choice.kind == "toggle" then
      config.enabled = not aan
      teams_write_config(config)
      vim.notify("Teams-meldingen " .. (config.enabled and "AAN" or "UIT"), vim.log.levels.INFO)
      return
    end

    local e = config.editions[choice.code]
    local recipient_items = {}
    local default_label = teams_email(e.default_email)
      and teams_recipient_label(config, e.default_email) or "geen melding"
    table.insert(recipient_items, {
      kind = "default",
      label = "Standaardontvanger — " .. default_label,
    })
    for _, person in ipairs(teams_known_recipients(config)) do
      if not teams_same_email(person.email, e.default_email) then
        table.insert(recipient_items, {
          kind = "recipient",
          email = person.email,
          label = person.name == person.email
            and person.email or string.format("%s <%s>", person.name, person.email),
        })
      end
    end
    table.insert(recipient_items, {
      kind = "off",
      label = "Geen melding voor deze editie",
    })
    table.insert(recipient_items, {
      kind = "new",
      label = "Nieuwe vervanger toevoegen…",
    })
    table.insert(recipient_items, {
      kind = "back",
      label = "← Terug naar krantenoverzicht",
    })

    local function save_email(email)
      e.email = email or vim.NIL
      teams_write_config(config)
      local nieuw = (e.email == vim.NIL) and "geen melding" or tostring(e.email or "geen melding")
      vim.notify(string.format("%s → %s", e.krant or choice.code, nieuw), vim.log.levels.INFO)
    end

    vim.ui.select(recipient_items, {
      prompt = "Teams-ontvanger voor " .. (e.krant or choice.code) .. ":",
      format_item = function(item) return item.label end,
    }, function(recipient_choice)
      if not recipient_choice then return end
      if recipient_choice.kind == "back" then
        vim.schedule(M.teams_redactie)
      elseif recipient_choice.kind == "default" then
        save_email(teams_email(e.default_email))
      elseif recipient_choice.kind == "off" then
        save_email(nil)
      elseif recipient_choice.kind == "recipient" then
        save_email(recipient_choice.email)
      elseif recipient_choice.kind == "new" then
        vim.ui.input({ prompt = "Naam van de nieuwe vervanger: " }, function(name)
          if name == nil then return end
          name = vim.trim(name)
          if name == "" then
            vim.notify("Naam is verplicht; vervanger niet opgeslagen", vim.log.levels.ERROR)
            return
          end
          vim.ui.input({ prompt = "E-mailadres van " .. name .. ": " }, function(email)
            if email == nil then return end
            email = vim.trim(email)
            if not teams_valid_email(email) then
              vim.notify("Geen geldig e-mailadres; vervanger niet opgeslagen", vim.log.levels.ERROR)
              return
            end
            teams_store_recipient(config, name, email)
            save_email(email)
          end)
        end)
      end
    end)
  end)
end

vim.api.nvim_create_user_command("TeamsRedactie", M.teams_redactie, {
  desc = "Teams-meldingen: ontvanger kiezen, vervanger opslaan of aan/uit",
  force = true,
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
  -- Alleen de kale artikelbody als AI-input — geen frontmatter, kopcodes of
  -- eerder gegenereerde secties (voorkomt dat bijv. "Fotograaf:" in de post lekt).
  local _, _, body = split_article_parts(lines)
  local article_text = table.concat(body, "\n")
  local fb_prompt = _112_signal_score(article_text) >= _112_THRESHOLD and "facebook_bericht_112" or "facebook_bericht"

  ai_system(
    { aitext, fb_prompt },
    { text = true, stdin = article_text },
    function(result)
      vim.schedule(function()
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
    "AI · Facebook",
    buf
  )
end

vim.keymap.set("n", "<leader>af", M.generate_facebook, {
  desc = "Facebooktekst genereren en ter controle tonen",
})


-- <leader>ao — tekstcheck: alleen objectieve spel-/grammaticafouten worden
-- gefixt; twijfelgevallen komen als ## Suggesties onderaan (worden door
-- pubble-send automatisch gestript, dus hoeven nooit opgeruimd te worden).
function M.tekstcheck()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  sections = drop_suggestions_block(sections)

  ai_system(
    { aitext, "tekstcheck" },
    { text = true, stdin = table.concat(body, "\n") },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          vim.notify("Tekstcheck mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
          return
        end
        local new_body = vim.split(result.stdout, "\n", { plain = true })
        while #new_body > 0 and vim.trim(new_body[#new_body]) == "" do table.remove(new_body) end
        vim.api.nvim_buf_set_lines(
          buf, 0, -1, false,
          reassemble_article(fm, ctrl, new_body, sections, has_boundary)
        )
      end)
    end,
    "AI · Tekstcheck",
    buf
  )
end

vim.keymap.set("n", "<leader>ao", M.tekstcheck, {
  desc = "Tekstcheck: spelling/grammatica; twijfelgevallen als suggesties onderaan",
})

-- Scan de body in alinea's (blokken gescheiden door lege regels).
-- Geeft per alinea: s = eerste regel, e = laatste regel, heading = of het
-- een losse **vetgedrukte** regel is (tussenkop of vette lead).
local function scan_paragraphs(body)
  local paras = {}
  local i = 1
  while i <= #body do
    if vim.trim(body[i]) == "" then
      i = i + 1
    else
      local start_i = i
      while i <= #body and vim.trim(body[i]) ~= "" do i = i + 1 end
      local text = vim.trim(body[start_i])
      table.insert(paras, {
        s = start_i,
        e = i - 1,
        heading = (i - 1 == start_i) and text:match("^%*%*.+%*%*$") ~= nil,
      })
    end
  end
  return paras
end

-- Voeg tussenkopjes deterministisch in. `koppen` is een lijst {n=…, kop=…}
-- (kop hoort direct bóven alinea n). Ongeldige posities worden overgeslagen:
-- boven kop/lead, direct na de intro (n=3) of boven de laatste alinea.
-- Invoegen van achter naar voren zodat de alinea-indexen geldig blijven.
local function insert_headings(body, koppen, paras)
  table.sort(koppen, function(a, b) return a.n > b.n end)
  local out = {}
  for i, l in ipairs(body) do out[i] = l end
  for _, k in ipairs(koppen) do
    if k.n >= 4 and k.n <= #paras - 1 then
      table.insert(out, paras[k.n].s, "")
      table.insert(out, paras[k.n].s, "**" .. k.kop .. "**")
    end
  end
  return out
end

-- Plaats een streamer deterministisch rond het inhoudelijke midden. De eerste
-- bodyalinea is de kop; de tweede is de lead/eerste tekstalinea en telt mee,
-- ook wanneer die vet staat. Losse vetregels verderop zijn tussenkoppen en
-- tellen niet mee. De streamer komt nooit direct na die eerste tekstalinea,
-- nooit na de laatste tekstalinea en nooit direct naast een **tussenkop**.
-- Web maakt er een quote-widget van, print een <<STREAMER>>-markering — beide
-- op dezelfde plek.
local function insert_streamer_midway(body, streamer_text)
  local paras = scan_paragraphs(body)
  local prose = {}
  for i = 2, #paras do
    -- Alinea 2 is de lead; scan_paragraphs markeert een vette lead technisch
    -- als heading, maar inhoudelijk blijft dit de eerste tekstalinea.
    if i == 2 or not paras[i].heading then
      table.insert(prose, i)
    end
  end
  if #prose < 3 then return nil end  -- geen veilige grens rond het midden

  -- Kandidaatgrens = invoegen na een echte tekstalinea. Positie 1 (de lead)
  -- en de laatste positie vallen altijd af. Zoek vanaf het midden naar buiten.
  local mid = math.ceil(#prose / 2)
  local best
  for d = 0, #prose do
    for _, prose_pos in ipairs(d == 0 and { mid } or { mid + d, mid - d }) do
      if prose_pos >= 2 and prose_pos <= #prose - 1 then
        local para_idx = prose[prose_pos]
        if not paras[para_idx + 1].heading then
          best = para_idx
          break
        end
      end
    end
    if best then break end
  end
  if not best then
    return nil
  end

  local out = {}
  for idx, l in ipairs(body) do
    table.insert(out, l)
    if idx == paras[best].e then
      table.insert(out, "")
      table.insert(out, "> " .. streamer_text)
    end
  end
  return out
end

-- <leader>at — tussenkopjes + streamer, als twee gelijktijdige korte AI-calls.
-- De AI levert alleen kopjes-met-positie ("3: Kopje") en één streamerregel —
-- de artikeltekst zelf wordt nooit door de AI geregenereerd; alle invoeging
-- is deterministisch. De streamer-call wordt overgeslagen als er al een
-- eigen >-streamer in de tekst staat.
function M.tussenkopjes_streamer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  local paras = scan_paragraphs(body)

  local has_streamer = false
  for _, l in ipairs(body) do
    if l:match("^>%s") or vim.trim(l) == ">" then has_streamer = true; break end
  end

  local body_text = table.concat(body, "\n")

  -- Genummerde variant voor de tussenkopjes-prompt: elke alinea krijgt een
  -- [N]-marker zodat de AI posities kan teruggeven i.p.v. de hele tekst.
  local numbered = {}
  for i, l in ipairs(body) do numbered[i] = l end
  for n, p in ipairs(paras) do
    numbered[p.s] = "[" .. n .. "] " .. numbered[p.s]
  end
  local numbered_text = table.concat(numbered, "\n")

  local results = { koppen = nil, streamer = nil }
  local pending = has_streamer and 1 or 2

  local function finish()
    if pending > 0 then return end

    -- Parse "N: Kopje"-regels; alles wat niet matcht (incl. GEEN) valt af.
    local koppen = {}
    for _, l in ipairs(vim.split(results.koppen or "", "\n", { plain = true })) do
      local n, kop = l:match("^%s*%[?(%d+)%]?%s*[:%.%)]%s*(.+)$")
      if n and kop then
        kop = vim.trim(kop):gsub("^%*+", ""):gsub("%*+$", ""):gsub("%.$", "")
        if kop ~= "" then table.insert(koppen, { n = tonumber(n), kop = kop }) end
      end
    end

    local new_body = insert_headings(body, koppen, paras)
    if #koppen == 0 then
      vim.notify("Geen tussenkopjes toegevoegd (artikel te kort of AI gaf niets terug).", vim.log.levels.INFO)
    end

    if results.streamer and results.streamer ~= "" then
      local with_streamer = insert_streamer_midway(new_body, results.streamer)
      if with_streamer then
        new_body = with_streamer
      else
        vim.notify("Artikel te kort voor een mid-tekst streamer — overgeslagen.", vim.log.levels.WARN)
      end
    end
    vim.api.nvim_buf_set_lines(
      buf, 0, -1, false,
      reassemble_article(fm, ctrl, new_body, sections, has_boundary)
    )
    if has_streamer then
      vim.notify("Tussenkopjes toegevoegd; eigen > streamer blijft staan.", vim.log.levels.INFO)
    end
  end

  ai_system(
    { aitext, "tussenkopjes" },
    { text = true, stdin = numbered_text },
    function(result)
      vim.schedule(function()
        if result.code == 0 then
          results.koppen = result.stdout
        else
          vim.notify("Tussenkopjes mislukt: " .. (result.stderr or ""), vim.log.levels.WARN)
        end
        pending = pending - 1
        finish()
      end)
    end,
    "AI · Tussenkopjes",
    buf
  )

  if not has_streamer then
    ai_system(
      { aitext, "streamer" },
      { text = true, stdin = body_text },
      function(result)
        vim.schedule(function()
          if result.code == 0 then
            -- Eerste niet-lege regel = de streamertekst.
            for _, l in ipairs(vim.split(result.stdout or "", "\n", { plain = true })) do
              if vim.trim(l) ~= "" then results.streamer = vim.trim(l); break end
            end
          else
            vim.notify("Streamer genereren mislukt — alleen tussenkopjes toegepast.", vim.log.levels.WARN)
          end
          pending = pending - 1
          finish()
        end)
      end,
      "AI · Streamer",
      buf
    )
  end
end

vim.keymap.set("n", "<leader>at", M.tussenkopjes_streamer, {
  desc = "Tussenkopjes + streamer (streamer alleen als er nog geen > staat)",
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


-- <leader>ap — Ad-hoc rewrite: vervang de artikelBODY door AI-herschreven tekst.
-- Usage: type *** on a new line, then your instruction, then press <leader>ap.
-- Frontmatter, kopcodes en ## secties blijven onaangeraakt (canonieke splitser).
function M.ai_prompt_rewrite()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local article_lines = {}
  do
    -- Marker + instructie afsplitsen vóór de deelsplitsing.
    local marker_idx = nil
    for i = #lines, 1, -1 do
      if vim.trim(lines[i]) == "***" then marker_idx = i; break end
    end
    if not marker_idx then
      vim.notify("Type *** on a new line followed by your instruction first.", vim.log.levels.WARN)
      return
    end
    for i = 1, marker_idx - 1 do table.insert(article_lines, lines[i]) end
  end
  local _, prompt = split_on_prompt_marker(lines)
  if not prompt or prompt == "" then
    vim.notify("Type *** on a new line followed by your instruction first.", vim.log.levels.WARN)
    return
  end

  local fm, ctrl, body, sections, has_boundary = split_article_parts(article_lines)

  ai_system(
    { aichat, prompt, "--mode", "rewrite" },
    { text = true, stdin = table.concat(body, "\n") },
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
        local new_body = vim.split(output, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(
          buf, 0, -1, false,
          reassemble_article(fm, ctrl, new_body, sections, has_boundary)
        )
        vim.notify("Done. Use u to undo.", vim.log.levels.INFO)
      end)
    end,
    "AI · Herschrijven",
    buf
  )
end

vim.keymap.set("n", "<leader>ap", M.ai_prompt_rewrite, {
  desc = "Artikel herschrijven met eigen ***-instructie",
})


-- <leader>ag — AI gesprek: append AI answer below current *** prompt.
-- Builds full conversation history from prior *** / --- blocks.
function M.ai_chat()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local article, history, prompt = parse_conversation(lines)

  if prompt == "" then
    vim.notify("Type *** on a new line followed by your question first.", vim.log.levels.WARN)
    return
  end

  -- Ook een gesprek krijgt uitsluitend de artikelbody als context. Het
  -- tagblok, frontmatter en de zichtbare grens blijven lokaal in de buffer.
  local _, _, article_body = split_article_parts(
    vim.split(article, "\n", { plain = true })
  )
  article = table.concat(article_body, "\n")


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

        local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
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

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, current)
        -- Place cursor at end so user can type the next ***
        local last = #vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        if vim.api.nvim_get_current_buf() == buf then
          vim.api.nvim_win_set_cursor(0, { last, 0 })
        end
        vim.notify("Answer added. Type *** + next question, then <leader>ag.", vim.log.levels.INFO)
      end)
    end,
    "AI · Gesprek",
    buf
  )
end

vim.keymap.set("n", "<leader>ag", M.ai_chat, {
  desc = "AI-gesprek via *** over artikel voeren",
})



-- <leader>ah — centraal, hiërarchisch hulpmenu. De eerste laag bevat alleen
-- herkenbare categorieën; de tweede laag bevat de concrete codes of acties.
-- Houd editie-items synchroon met pubble_publications.py.
local help_categories = {
  {
    label = "Edities",
    prompt = "Editie invoegen:",
    items = {
      { label = "De Brug (B, standaard)", insert = "editie: B" },
      { label = "De Swollenaer (SW)", insert = "editie: SW" },
      { label = "De Stadskoerier (ST)", insert = "editie: ST" },
      { label = "Zeewolde Actueel (Z)", insert = "editie: Z" },
      { label = "De Drontenaar (D)", insert = "editie: D" },
      { label = "Nieuwsbode de Kop (K)", insert = "editie: K" },
      { label = "Alle edities", insert = "editie: all" },
      { label = "Overijssel (B, SW, ST, K)", insert = "editie: overijssel" },
      { label = "Flevoland (D, Z)", insert = "editie: flevoland" },
    },
  },
  {
    label = "Publicatieplanning",
    prompt = "Publicatieplanning invoegen:",
    items = {
      { label = "Prioriteit 1 — moet mee", insert = "prio: 1" },
      { label = "Prioriteit 2 — mag mee", insert = "prio: 2" },
      { label = "Prioriteit 3 — rest (standaard)", insert = "prio: 3" },
      { label = "Prioriteit 4 — nood", insert = "prio: 4" },
      { label = "Uiterste publicatieweek — x betekent geen deadline", insert = "week: " },
    },
  },
  {
    label = "Foto en vormgeving",
    prompt = "Foto of vormgeving:",
    items = {
      { label = "Bijschrift invoeren (globaal, alle foto's)", insert = "Bijschrift: " },
      { label = "Fotograaf of fotocredit invoeren (globaal)", insert = "Foto: " },
      { label = "Bijschrift foto 1 (b1:)", insert = "b1: " },
      { label = "Fotograaf foto 1 (c1:)", insert = "c1: " },
      { label = "Bijschrift foto 2 (b2:)", insert = "b2: " },
      { label = "Fotograaf foto 2 (c2:)", insert = "c2: " },
      { label = "Foto's: nummer ze foto1/foto2 → koppelt aan b1/c1, b2/c2 (Inbox)", insert = "" },
      { label = "Eigen streamer op cursorpositie invoeren", action = function() M.insert_streamer_at_cursor() end },
    },
  },
  {
    label = "Publicatie-extra's",
    prompt = "Publicatie-extra invoegen:",
    items = {
      { label = "Rubriek 112", insert = "rubriek: 112" },
      { label = "Kalenderitem laten maken", insert = "calendar: x" },
      { label = "Facebooktekst door AI laten maken", insert = "facebook: x" },
      { label = "Eigen Facebooktekst schrijven", action = function() M.edit_facebook_text() end },
    },
  },
  {
    label = "Acties",
    prompt = "Actie starten:",
    items = {
      { label = "Artikel herschrijven (<leader>ar)", action = function() M.rewrite_article_buffer() end },
      { label = "Tekstcheck (<leader>ao)", action = function() M.tekstcheck() end },
      { label = "Tussenkopjes en streamer (<leader>at)", action = function() M.tussenkopjes_streamer() end },
      { label = "Eigen opdracht via *** (<leader>ap)", action = function() M.ai_prompt_rewrite() end },
      { label = "AI-gesprek via *** (<leader>ag)", action = function() M.ai_chat() end },
      { label = "Teams-meldingen beheren", action = function() M.teams_redactie() end },
    },
  },
  {
    label = "Volledige cheatsheet",
    action = function() M.show_cheatsheet() end,
  },
}

local function insert_snippet_above_cursor(text)
  if text == "" then return end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, line in ipairs(lines) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      vim.api.nvim_buf_set_lines(0, i - 1, i - 1, false, { text })
      vim.api.nvim_win_set_cursor(0, { i, #text })
      if text:sub(-1) == " " then vim.cmd("startinsert!") end
      return
    end
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { text })
  vim.api.nvim_win_set_cursor(0, { row, #text })
  if text:sub(-1) == " " then
    vim.cmd("startinsert!")
  end
end

function M.insert_streamer_at_cursor()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local boundary
  local title_row
  local first_section
  for index, line in ipairs(lines) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      boundary = index
    elseif boundary and not title_row and vim.trim(line) ~= "" then
      title_row = index
    elseif boundary and line:match("^## ") then
      first_section = index
      break
    end
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if boundary and (row <= (title_row or boundary)
      or (first_section and row >= first_section)) then
    vim.notify(
      "Zet de cursor in de lopende artikeltekst waar de streamer moet komen.",
      vim.log.levels.WARN
    )
    return
  end
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, { "> " })
  vim.api.nvim_win_set_cursor(0, { row, 2 })
  vim.cmd("startinsert!")
end

function M.edit_facebook_text()
  local buf = vim.api.nvim_get_current_buf()
  strip_leading_control_line(buf, "^[Ff]acebook%s*:%s*x%s*$")
  strip_leading_control_line(buf, "^[Ff]acebook_tekst%s*:")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:match("^## Facebook%s*$") then
      local line_after = index + 1
      if lines[line_after] == nil or lines[line_after] ~= "" then
        vim.api.nvim_buf_set_lines(0, index, index, false, { "" })
      end
      vim.api.nvim_win_set_cursor(0, { line_after, 0 })
      vim.cmd("startinsert!")
      return
    end
  end

  while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
  for _, line in ipairs({ "", "---", "", "## Facebook", "" }) do
    table.insert(lines, line)
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  vim.cmd("startinsert!")
end

function M.show_meta_cheatsheet()
  vim.ui.select(help_categories, {
    prompt = "Texttools hulp:",
    format_item = function(i) return i.label end,
  }, function(category)
    if not category then return end
    if category.action then
      category.action()
      return
    end
    local submenu = {}
    for _, item in ipairs(category.items) do table.insert(submenu, item) end
    table.insert(submenu, { label = "← Terug naar hoofdmenu", back = true })
    vim.ui.select(submenu, {
      prompt = category.prompt,
      format_item = function(i) return i.label end,
    }, function(item)
      if not item then return end
      if item.back then
        -- Plan het hoofdmenu na het sluiten van de huidige picker; sommige
        -- vim.ui.select-implementaties kunnen niet twee vensters tegelijk wisselen.
        vim.schedule(M.show_meta_cheatsheet)
      elseif item.action then
        item.action()
      else
        insert_snippet_above_cursor(item.insert)
      end
    end)
  end)
end

vim.keymap.set("n", "<leader>ah", M.show_meta_cheatsheet, {
  desc = "Texttools hulp: codes, acties en volledige cheatsheet",
})


-- Volledige texttools-cheatsheet, geopend vanuit het centrale <leader>ah-menu.
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

return M
