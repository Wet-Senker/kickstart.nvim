local M = {}
local notifications = require("texttools_notify")
local article_recognition = require("article_recognition")
local texttools_paths = require("texttools_paths")

-- Nieuwe pv-imports leven in de gedeelde werkmap. Desktop blijft als
-- compatibele invoerroute bestaan voor oude bestanden en handmatig geopende
-- Markdown, maar is niet langer de standaardopslag. Neovim canonicaliseert
-- paden bij onder meer --remote; registreer daarom zowel het zichtbare
-- symlinkpad als het echte iCloud-pad.
local function normalized_path(path)
  if type(path) ~= "string" or path == "" then return "" end
  local absolute = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  return vim.fs.normalize(vim.fn.resolve(absolute))
end

local function import_patterns_for(directory)
  local visible = vim.fs.normalize(
    vim.fn.fnamemodify(vim.fn.expand(directory), ":p")
  ):gsub("/+$", "")
  local canonical = normalized_path(directory):gsub("/+$", "")
  local patterns = { visible .. "/*.md" }
  if canonical ~= visible then table.insert(patterns, canonical .. "/*.md") end
  return patterns
end

local import_patterns = {}
for _, directory in ipairs({ vim.fn.expand("~/Desktop"), texttools_paths.work() }) do
  for _, pattern in ipairs(import_patterns_for(directory)) do
    table.insert(import_patterns, pattern)
  end
end
M._import_patterns = import_patterns

-- Alleen editor-AI-processen zijn met <leader>aq annuleerbaar. Pubble-writes,
-- uploads en archivering staan bewust niet in deze lijst: die kunnen extern al
-- effect hebben gehad en moeten hun idempotente herstelroute afmaken.
local active_ai_jobs = {}
local next_ai_job_id = 0
local AI_CANCELLED = "__AI_CANCELLED__"

-- Normale workflowbevestigingen horen de redactieflow niet te onderbreken.
-- Fidget toont ze tijdelijk in een zwevend venster; vim.notify kan bij lange
-- regels terugvallen op de commandoregel en daardoor om Enter vragen.
local function notify_workflow(message, level, options)
  notifications.workflow(message, level, options)
end

local function open_published_url(url)
  local ok, _, open_error = pcall(vim.ui.open, url)
  if ok and not open_error then return true end
  local detail = vim.trim(tostring(open_error or _ or ""))
  vim.notify(
    "Pubble-pagina kon niet worden geopend"
      .. (detail ~= "" and (": " .. detail) or "."),
    vim.log.levels.WARN
  )
  return false
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
    notify_workflow(message, vim.log.levels.INFO)
  end)
  return true
end

-- Maak de gedeelde werk- en batchmappen aan als een importbestand wordt geopend.
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = import_patterns,
  callback = function()
    local inbox = texttools_paths.inbox()
    vim.fn.mkdir(texttools_paths.work(), "p")
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
    notify_workflow("Geen actieve AI-taak in deze buffer.", vim.log.levels.INFO)
  end
end, {
  desc = "Actieve AI-taak in huidige buffer annuleren",
})

vim.api.nvim_create_user_command("AICancel", function()
  if not M.cancel_ai(vim.api.nvim_get_current_buf()) then
    notify_workflow("Geen actieve AI-taak in deze buffer.", vim.log.levels.INFO)
  end
end, { desc = "Actieve AI-taak in huidige buffer annuleren" })

local texttools_commands = require("texttools_commands")
local layout_export = require("layout_export")
local aitext = texttools_commands.bin("aitext")
local kampen_fix = texttools_commands.bin("kampen-fix")
local redactie_adres = texttools_commands.bin("redactie-adres")
local article_dateline = texttools_commands.bin("article-dateline")
local article_headline = texttools_commands.bin("article-headline")
local teams_config_cli = texttools_commands.bin("teams-config")
local aichat = texttools_commands.bin("aichat")
local articlemeta = texttools_commands.bin("articlemeta")
local pubble_send = texttools_commands.bin("pubble-send")
local pubble_schedule = texttools_commands.bin("pubble-schedule")
local pubble_event = texttools_commands.bin("pubble-event")
local texttools_python = texttools_commands.bin("python")
local publication_links_module = "texttools.publication_links_cli"
local ARTICLE_BOUNDARY = "=== ARTIKEL ==="

local function publication_status_from_output(stdout, stderr)
  local combined = (stdout or "") .. "\n" .. (stderr or "")
  local raw = combined:match("PUBBLE_RESULT_JSON:%s*(%b{})")
  if not raw then return nil end
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok or type(decoded) ~= "table" or type(decoded.phases) ~= "table" then
    return nil
  end
  return decoded
end

local PUBLICATION_PHASE_LABELS = {
  newspaper = "krant",
  web = "website",
  calendar = "agenda",
  social = "Facebook/LinkedIn",
  media = "media",
  teams = "Teams",
}

local function failed_publication_labels(status)
  local labels = {}
  if type(status) ~= "table" or type(status.phases) ~= "table" then return labels end
  for _, phase in ipairs(status.phases) do
    if type(phase) == "table" and phase.status == "failed" then
      table.insert(labels, PUBLICATION_PHASE_LABELS[phase.name] or tostring(phase.name))
    end
  end
  return labels
end

M._publication_status_from_output = publication_status_from_output
M._failed_publication_labels = failed_publication_labels
M._open_published_url = open_published_url

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
  koppel=true, ontkoppel=true, suggestiereden=true,
  agenda=true, calendar=true, cal=true,
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
M._is_control_key = _is_control_key

-- Agenda-schakelaar uit de controleregels lezen (mirror van agenda_mode in
-- calendar_signal.py). Retourneert "on" | "off" | "auto".
local _AGENDA_ON = { x=true, ja=true, aan=true, t=true, ["true"]=true, yes=true, y=true }
local _AGENDA_OFF = { f=true, nee=true, ["false"]=true, geen=true, uit=true, no=true, n=true }
local function _agenda_mode_from_lines(lines)
  local mode = "auto"
  for _, line in ipairs(lines) do
    local t = vim.trim(line)
    if t == "" or t == ARTICLE_BOUNDARY or t == "---" then
      -- leeg/grens: controleblok is uit; niet verder kijken in de body
      if t == ARTICLE_BOUNDARY or t == "---" then break end
    else
      local k, v = t:match("^(%a[%a%d_]*)%s*:%s*(.-)%s*$")
      if k then
        k = k:lower()
        if k == "agenda" or k == "cal" or k == "calendar" then
          v = (v or ""):lower()
          if _AGENDA_OFF[v] then mode = "off"
          elseif _AGENDA_ON[v] then mode = "on"
          else mode = "auto" end
        end
      end
    end
  end
  return mode
end
M._agenda_mode_from_lines = _agenda_mode_from_lines

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

-- Verwijder alle genoemde besturingsregels boven de artikelgrens. Dit wordt
-- gebruikt nadat een koppel-/ontkoppelopdracht expliciet is afgehandeld;
-- andere metadata en de e:-regel blijven onaangeroerd.
local function strip_leading_control_keys(buf, keys)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, body_start = split_frontmatter_lines(lines)
  local marker_index = nil
  for i = body_start, #lines do
    if vim.trim(lines[i]) == ARTICLE_BOUNDARY then
      marker_index = i
      break
    end
  end
  local last = marker_index and (marker_index - 1) or (body_start - 1)
  if not marker_index then
    for i = body_start, #lines do
      if vim.trim(lines[i]) == "" then break end
      last = i
    end
  end
  local changed = false
  for i = last, body_start, -1 do
    local key = vim.trim(lines[i]):match("^([%a][%a%d_]*)%s*:")
    if key and keys[key:lower()] then
      table.remove(lines, i)
      changed = true
    end
  end
  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  end
  return changed
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

-- Een import mag niet per ongeluk vrijwel onbewerkt naar Pubble. Vergelijk
-- uitsluitend de artikelbody: editiecodes, metadata, foto's, kalender- en
-- socialsecties zijn workflowdata en tellen niet als redactionele bewerking.
local SEND_SAFEGUARD_CHANGE_THRESHOLD = 0.15

local function editorial_body_text(lines)
  local _, _, body = split_article_parts(lines)
  return vim.trim(table.concat(body, "\n"))
end

local function normalized_editorial_tokens(text)
  local normalized = vim.fn.tolower(text or ""):gsub("[%c%s]+", " ")
  local tokens = {}
  for token in normalized:gmatch("%S+") do
    token = token:gsub("^%p+", ""):gsub("%p+$", "")
    if token ~= "" then table.insert(tokens, token) end
  end
  return tokens
end

local function editorial_shingles(text)
  local tokens = normalized_editorial_tokens(text)
  local width = math.min(3, #tokens)
  local shingles = {}
  if width == 0 then return shingles end
  for index = 1, #tokens - width + 1 do
    local key = table.concat(tokens, "\31", index, index + width - 1)
    shingles[key] = (shingles[key] or 0) + 1
  end
  return shingles
end

local function substantially_changed_since_import(original, current)
  local before = editorial_shingles(original)
  local after = editorial_shingles(current)
  local intersection = 0
  local union = 0
  local seen = {}
  for shingle, before_count in pairs(before) do
    local after_count = after[shingle] or 0
    intersection = intersection + math.min(before_count, after_count)
    union = union + math.max(before_count, after_count)
    seen[shingle] = true
  end
  for shingle, after_count in pairs(after) do
    if not seen[shingle] then union = union + after_count end
  end
  if union == 0 then return false end
  local changed = union - intersection
  local required = math.max(3, math.ceil(union * SEND_SAFEGUARD_CHANGE_THRESHOLD))
  return changed >= required
end

local function capture_import_baseline(buf)
  if not vim.api.nvim_buf_is_valid(buf)
      or type(vim.b[buf].send_import_body) == "string" then
    return
  end
  vim.b[buf].send_import_body = editorial_body_text(
    vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  )
  vim.b[buf].send_ai_rewrite_completed = false
  vim.b[buf].send_ai_neutrality_body_hash = nil
  vim.b[buf].send_safeguard_approved_body = nil
end

local function mark_ai_rewrite_completed(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.b[buf].send_ai_rewrite_completed = true
  vim.b[buf].send_ai_neutrality_body_hash = nil
  vim.b[buf].send_safeguard_approved_body = nil
end

local function mark_ai_neutrality_completed(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  lines = lines or vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  vim.b[buf].send_ai_neutrality_body_hash = vim.fn.sha256(editorial_body_text(lines))
  vim.b[buf].send_safeguard_approved_body = nil
end

local function send_safeguard_reason(buf, lines)
  local imported = vim.b[buf].send_import_body
  if type(imported) ~= "string" then return nil end

  local current = editorial_body_text(lines)
  local current_hash = vim.fn.sha256(current)
  if vim.b[buf].send_safeguard_approved_body == current_hash then return nil end

  local neutrality_hash = vim.b[buf].send_ai_neutrality_body_hash
  if type(neutrality_hash) == "string" and neutrality_hash == current_hash then
    return nil
  end

  local rewritten = vim.b[buf].send_ai_rewrite_completed == true
  local changed = substantially_changed_since_import(imported, current)
  -- De safeguard beschermt tegen vrijwel ongeredigeerd doorplaatsen, niet
  -- tegen handmatig redigeren. Een aantoonbaar substantiële bodywijziging is
  -- daarom zelfstandig voldoende; AI is geen publicatievoorwaarde.
  if changed then return nil end
  if type(neutrality_hash) == "string" then
    return "De artikeltekst is na de journalistieke neutraliteitscontrole weer "
      .. "gewijzigd en wijkt nog nauwelijks af van de oorspronkelijke import."
  end
  if not rewritten and not changed then
    return "Deze geïmporteerde artikeltekst is niet volledig door AI herschreven "
      .. "en wijkt nog nauwelijks af van de import."
  end
  return "De AI-herschrijving is voltooid, maar de artikeltekst wijkt volgens "
    .. "de tekstvergelijking nog nauwelijks af van de import."
end

M._send_safeguard_confirm = function(reason)
  return vim.fn.confirm(
    "Extra verzendcontrole\n\n" .. reason .. "\n\nToch publiceren?",
    "&Ja\n&Nee",
    2
  )
end

local function confirm_send_safeguard(buf, lines)
  local reason = send_safeguard_reason(buf, lines)
  if not reason then return true end
  if M._send_safeguard_confirm(reason) ~= 1 then
    notify_workflow("Verzending geannuleerd; controleer of herschrijf de artikeltekst.")
    return false
  end
  vim.b[buf].send_safeguard_approved_body = vim.fn.sha256(editorial_body_text(lines))
  return true
end

-- Inspecteerbare testpunten; de productieflow gebruikt exact dezelfde logica.
M._editorial_body_text = editorial_body_text
M._substantially_changed_since_import = substantially_changed_since_import
M._capture_import_baseline = capture_import_baseline
M._mark_ai_rewrite_completed = mark_ai_rewrite_completed
M._mark_ai_neutrality_completed = mark_ai_neutrality_completed
M._send_safeguard_reason = send_safeguard_reason
M._confirm_send_safeguard = confirm_send_safeguard

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
local _112_THRESHOLD = article_recognition.EMERGENCY_THRESHOLD

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
-- Deterministische kalenderdetectie. De centrale herkenningsmodule bezit de
-- scorelogica; ai_text voert alleen de eventuele metadata-actie uit.
local _CALENDAR_THRESHOLD = article_recognition.CALENDAR_THRESHOLD

local function _calendar_signal_score(text)
  return article_recognition.calendar_signal_score(text)
end

M._calendar_signal_score = _calendar_signal_score

-- Een automatische BufReadPost-vraag mag niet via de fzf-lua
-- vim.ui.select-provider lopen: die kan tijdens een verse embedded TUI-sessie
-- de eventloop bezet houden. De ingebouwde confirm-dialoog is hiervoor klein,
-- synchroon en betrouwbaar. Dit testpunt is injecteerbaar in headless tests.
M._calendar_date_confirm = function(date_count)
  return vim.fn.confirm(
    string.format(
      "Tekst bevat %d verschillende datums. Is dit één agenda-item voor de website?",
      date_count
    ),
    "&Ja — online agenda-item maken\n&Nee — geen online agenda-item",
    2
  )
end

M._112_confirm = function(prompt)
  return vim.fn.confirm(prompt, "&Ja\n&Nee", 2)
end

M._rubric_confirm = function(decision)
  local buttons = {}
  for index, candidate in ipairs(decision.candidates or {}) do
    table.insert(
      buttons,
      string.format("&%d %s (score %d)", index, candidate.label, candidate.confidence)
    )
  end
  table.insert(buttons, "&Geen rubriektemplate toepassen")
  local choice = vim.fn.confirm(
    "Herkenning controleren:",
    table.concat(buttons, "\n"),
    #buttons
  )
  return (decision.candidates or {})[choice]
end

-- Compatibiliteitswrapper voor bestaande rewrite-, Facebook- en
-- voorbereidingsflows. Ook deze paden gebruiken daardoor exact de centrale
-- deterministische 112-score.
_112_signal_score = function(text)
  return article_recognition.emergency_signal_score(text)
end
M._112_signal_score = _112_signal_score

-- Bouw de zichtbare editiehulp. De SUGGESTIE-marker blijft bewust op de
-- e:-regel: door alleen dat woord te verwijderen accepteert de redacteur alle
-- codes erachter. De aparte redenregel is uitsluitend uitleg.
local function edition_control_lines(resolved)
  local seen, chosen, suggested = {}, {}, {}
  for _, code in ipairs(resolved.editions or {}) do
    if type(code) == "string" and not seen[code] then
      seen[code] = true
      table.insert(chosen, code)
    end
  end
  if type(resolved.suggestions) == "table" then
    for _, suggestion in ipairs(resolved.suggestions) do
      for _, code in ipairs(suggestion.editions or {}) do
        if type(code) == "string" and not seen[code] then
          seen[code] = true
          table.insert(suggested, code)
        end
      end
    end
  end
  if #chosen == 0 then return {} end

  local e_line = "e: " .. table.concat(chosen, ", ")
  if #suggested > 0 then
    e_line = e_line .. ", SUGGESTIE, " .. table.concat(suggested, ", ")
  end
  local result = { e_line }

  local reasons_by_edition = {}
  if type(resolved.suggestion_reasons) == "table" then
    for _, item in ipairs(resolved.suggestion_reasons) do
      if type(item.edition) == "string" and type(item.reasons) == "table" then
        reasons_by_edition[item.edition] = item.reasons
      end
    end
  end
  local reason_parts = {}
  for _, code in ipairs(suggested) do
    local reasons = reasons_by_edition[code]
    if type(reasons) == "table" and #reasons > 0 then
      table.insert(reason_parts, code .. " — " .. table.concat(reasons, ", "))
    end
  end
  if #reason_parts > 0 then
    table.insert(result, "suggestiereden: " .. table.concat(reason_parts, "; "))
  end
  return result
end
M._edition_control_lines = edition_control_lines

-- Vul (of vervang) de e:-controleregel op basis van dateline, plaatsenscan en
-- eigen onderwerp-koppelingen.
-- Draait direct na het herschrijven (<leader>ar) — dan is er een dateline en
-- een redelijk complete tekst. De regel wordt: `e: <kranten>, SUGGESTIE,
-- <suggesties>`. pubble-send negeert bij het versturen alles vanaf SUGGESTIE,
-- dus een suggestie gaat pas mee als de gebruiker die vóór SUGGESTIE zet.
-- Puur een hulpje: bij een fout stil overslaan, nooit de herschrijving breken.
local function fill_editions_line(buf, content, done)
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), tmp)
  start_buffer_job(buf)
  vim.system(
    { pubble_send, tmp, "--resolve-editions", "--require-article-boundary" },
    { text = true },
    function(res)
    vim.schedule(function()
      local function complete(ok)
        finish_buffer_job(buf)
        if done then done(ok) end
      end
      vim.fn.delete(tmp)
      local ok, r = pcall(vim.fn.json_decode, res.stdout or "")
      if res.code ~= 0 or not ok or type(r) ~= "table" or type(r.editions) ~= "table" then
        complete(false)
        return
      end

      local edition_lines = edition_control_lines(r)
      if #edition_lines == 0 then
        complete(false)
        return
      end

      -- Geen dateline herkend → e: valt terug op De Brug. Dat is precies de
      -- stille misser die een artikel per ongeluk naar B stuurt; hier, waar de
      -- e:-regel ontstaat, expliciet waarschuwen zodat het opvalt.
      if type(r.source) == "string" and r.source:match("^standaard") then
        notify_workflow(
          "LET OP: geen dateline herkend — e: staat standaard op De Brug. Klopt dat niet, pas e: aan.",
          vim.log.levels.WARN
        )
      end

      -- Bestaande e:/editie:-regel vervangen, anders bovenaan de controleregels.
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)

      local new_ctrl = {}
      for _, line in ipairs(edition_lines) do table.insert(new_ctrl, line) end
      for _, l in ipairs(ctrl) do
        local key = vim.trim(l):match("^([%a][%a%d_]*)%s*:")
        if not (key and (
          key:lower() == "e"
          or key:lower() == "editie"
          or key:lower() == "suggestiereden"
        )) then
          table.insert(new_ctrl, l)
        end
      end

      local out = reassemble_article(fm, new_ctrl, body, sections, has_boundary)

      -- Zet meteen het juiste redactie-mailadres voor de primaire editie
      -- (deterministisch, geen AI): net zo automatisch als de dateline zelf.
      -- Zo staat er onder een 112-/column-artikel voor Steenwijk direct
      -- redactiedekop@… i.p.v. de De Brug-default. De web-omzetting naar
      -- "via de knoppen hieronder" blijft een verzendstap.
      local primary = r.editions[1]
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
      complete(true)
    end)
    end
  )
end

local function same_edition_codes(left, right)
  if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
    return false
  end
  for index, code in ipairs(left) do
    if code ~= right[index] then return false end
  end
  return true
end

local function edition_names(codes, names)
  local labels = {}
  local fallback = {
    B = "De Brug",
    SW = "De Swollenaer",
    ST = "De Stadskoerier",
    Z = "Zeewolde Actueel",
    D = "De Drontenaar",
    K = "Nieuwsbode de Kop",
  }
  for index, code in ipairs(codes or {}) do
    table.insert(labels, (names and names[index]) or fallback[code] or code)
  end
  return table.concat(labels, " + ")
end

local function buffer_has_edition_control(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local _, controls = split_article_parts(lines)
  for _, line in ipairs(controls) do
    local key = vim.trim(line):match("^([%a][%a%d_]*)%s*:")
    if key and (key:lower() == "e" or key:lower() == "editie") then
      return true
    end
  end
  return false
end

local function replace_edition_control_lines(buf, edition_lines)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, controls, body, sections, has_boundary = split_article_parts(lines)
  local new_controls = {}
  for _, line in ipairs(edition_lines or {}) do
    table.insert(new_controls, line)
  end
  for _, line in ipairs(controls) do
    local key = vim.trim(line):match("^([%a][%a%d_]*)%s*:")
    key = key and key:lower() or nil
    if key ~= "e" and key ~= "editie" and key ~= "suggestiereden" then
      table.insert(new_controls, line)
    end
  end
  vim.api.nvim_buf_set_lines(
    buf, 0, -1, false,
    reassemble_article(fm, new_controls, body, sections, has_boundary)
  )
  return true
end

local function set_edition_codes(buf, codes)
  if type(codes) ~= "table" or #codes == 0 then return false end
  return replace_edition_control_lines(buf, { "e: " .. table.concat(codes, ", ") })
end

-- De Python-kern bepaalt óf en welke dateline inhoudelijk gerechtvaardigd is;
-- Lua past alleen het geretourneerde document op de zichtbare buffer toe.
local function ensure_detected_dateline(buf, detection)
  local place = type(detection) == "table" and detection.suggested_dateline or nil
  if type(place) ~= "string" or vim.trim(place) == ""
      or not vim.api.nvim_buf_is_valid(buf) then
    return true
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local result = vim.system(
    { article_dateline, "--place", place },
    { text = true, stdin = table.concat(lines, "\n") }
  ):wait(3000)
  if result.code ~= 0 or type(result.stdout) ~= "string" or result.stdout == "" then
    notify_workflow(
      "Dateline kon niet automatisch worden toegevoegd: "
        .. vim.trim(result.stderr or "onbekende fout"),
      vim.log.levels.WARN
    )
    return false
  end
  vim.api.nvim_buf_set_lines(
    buf, 0, -1, false,
    vim.split((result.stdout:gsub("\n$", "")), "\n", { plain = true })
  )
  return true
end

local function high_confidence_detection(resolved)
  local detection = type(resolved) == "table" and resolved.detection or nil
  if type(detection) ~= "table"
    or detection.confidence ~= "high"
    or type(detection.editions) ~= "table"
    or #detection.editions == 0
  then
    return nil
  end
  return detection
end

-- Eén asynchrone toegang tot de Python-resolver. De editor dupliceert de
-- verspreidingsgebiedentabel dus niet en de hoofdthread blijft ook op oudere
-- Macs vrij.
local function resolve_editions_for_content(buf, content, done)
  local tmp = vim.fn.tempname() .. ".md"
  vim.fn.writefile(vim.split(content, "\n", { plain = true }), tmp)
  start_buffer_job(buf)
  vim.system(
    { pubble_send, tmp, "--resolve-editions", "--require-article-boundary" },
    { text = true },
    function(res)
    vim.schedule(function()
      local function complete(resolved)
        finish_buffer_job(buf)
        if done then done(resolved) end
      end
      vim.fn.delete(tmp)
      local ok, resolved = pcall(vim.fn.json_decode, res.stdout or "")
      if res.code ~= 0
        or not ok
        or type(resolved) ~= "table"
        or type(resolved.editions) ~= "table"
      then
        complete(nil)
        return
      end
      complete(resolved)
    end)
    end
  )
end

-- Losse reviewbuffers zijn uitsluitend een NeoVim-weergave van het
-- UI-onafhankelijke Python-contract. Hashes, status, migratie en serialisatie
-- worden niet in Lua gedupliceerd.
local edition_review = require("edition_review").setup {
  python = texttools_python,
  notify = notify_workflow,
  start_job = start_buffer_job,
  finish_job = finish_buffer_job,
  resolve_editions = resolve_editions_for_content,
  send = function(source_buf) M.pubble_send(source_buf) end,
}

local function adapt_editorial_address(buf, primary)
  if not primary or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local adapted = vim.system(
    { redactie_adres, "--editie", primary },
    { text = true, stdin = table.concat(lines, "\n") }
  ):wait(3000)
  if adapted.code == 0 and adapted.stdout and adapted.stdout ~= "" then
    vim.api.nvim_buf_set_lines(
      buf, 0, -1, false,
      vim.split((adapted.stdout:gsub("\n$", "")), "\n", { plain = true })
    )
  end
end

-- De veilige variant voor import en <leader>av: bestaande keuzes blijven
-- staan en een stille De-Brug-default wordt niet als e:-regel vastgelegd.
local function fill_detected_editions_line(buf, content, done)
  resolve_editions_for_content(buf, content, function(resolved)
    if not resolved then
      if done then done(false) end
      return
    end
    if resolved.has_explicit_editions == true then
      adapt_editorial_address(buf, resolved.editions[1])
      if done then done(true) end
      return
    end
    local detection = high_confidence_detection(resolved)
    if detection then
      set_edition_codes(buf, detection.editions)
      ensure_detected_dateline(buf, detection)
      adapt_editorial_address(buf, detection.editions[1])
    end
    if done then done(true) end
  end)
end

M._edition_rewrite_confirm = function(current_label, detected_label, source)
  return vim.fn.confirm(
    "Bestemming na herschrijven controleren:\n\n"
      .. "Huidig: " .. current_label .. "\n"
      .. "Nieuwe detectie: " .. detected_label .. " (" .. source .. ")",
    "&Huidige behouden\n&Nieuwe gebruiken",
    1
  )
end

local function reconcile_editions_after_rewrite(buf, content, original_content, done)
  resolve_editions_for_content(buf, content, function(resolved)
    if not resolved then
      if done then done(false) end
      return
    end
    local detection = high_confidence_detection(resolved)
    if not detection then
      if done then done(true, resolved.editions, resolved.names) end
      return
    end
    if resolved.has_explicit_editions ~= true then
      set_edition_codes(buf, detection.editions)
      ensure_detected_dateline(buf, detection)
      adapt_editorial_address(buf, detection.editions[1])
      notify_workflow(
        "Bestemming herkend na herschrijven: "
          .. edition_names(detection.editions, detection.names) .. "."
      )
      if done then done(true, detection.editions, detection.names) end
      return
    end
    if same_edition_codes(resolved.editions, detection.editions) then
      if done then done(true, resolved.editions, resolved.names) end
      return
    end

    -- Een bestaande e:-regel is een bewuste redactiekeuze en mag best ruimer
    -- zijn dan de dateline. Vraag alleen wanneer de rewrite zélf de betrouwbare
    -- plaats-/regiodetectie veranderde. Zonder betrouwbare brondetectie is er
    -- niets te vergelijken en blijft de zichtbare keuze stil leidend.
    if type(original_content) ~= "string" or vim.trim(original_content) == "" then
      if done then done(true, resolved.editions, resolved.names) end
      return
    end
    resolve_editions_for_content(buf, original_content, function(original_resolved)
      local original_detection = high_confidence_detection(original_resolved)
      if not original_detection
        or same_edition_codes(original_detection.editions, detection.editions)
      then
        if done then done(true, resolved.editions, resolved.names) end
        return
      end

      local choice = M._edition_rewrite_confirm(
        edition_names(resolved.editions, resolved.names),
        edition_names(detection.editions, detection.names),
        detection.source or "inhoudelijke detectie"
      )
      if choice == 2 then
        set_edition_codes(buf, detection.editions)
        ensure_detected_dateline(buf, detection)
        adapt_editorial_address(buf, detection.editions[1])
        if done then done(true, detection.editions, detection.names) end
        return
      end
      if done then done(true, resolved.editions, resolved.names) end
    end)
  end)
end

local function edition_autodetect(buf, content)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].edition_recognition_done then return end
  vim.b[buf].edition_recognition_done = true
  if content:find("=== AGENDAPAGINA ===", 1, true) or buffer_has_edition_control(buf) then
    return
  end

  resolve_editions_for_content(buf, content, function(resolved)
    if not resolved
      or resolved.has_explicit_editions == true
      or not vim.api.nvim_buf_is_valid(buf)
      or buffer_has_edition_control(buf)
    then
      return
    end
    local detection = high_confidence_detection(resolved)
    if not detection then return end
    set_edition_codes(buf, detection.editions)
    ensure_detected_dateline(buf, detection)
    adapt_editorial_address(buf, detection.editions[1])
    notify_workflow(
      "Bestemming herkend bij import: "
        .. edition_names(detection.editions, detection.names)
        .. " ("
        .. (detection.source or "deterministische detectie")
        .. ")."
    )
  end)
end

local function drop_edition_versions_block(sections)
  local result = {}
  local skipping = false
  for _, line in ipairs(sections or {}) do
    if line:match("^## Editieversies%s*$") then
      skipping = true
    elseif skipping and line:match("^## %S") then
      skipping = false
      table.insert(result, line)
    elseif not skipping then
      table.insert(result, line)
    end
  end
  while #result > 0 and vim.trim(result[1]) == "" do table.remove(result, 1) end
  return result
end

local function has_edition_versions_block(sections)
  for _, line in ipairs(sections or {}) do
    if line:match("^## Editieversies%s*$") then return true end
  end
  return false
end

local function normalized_edition_variant(output)
  local text = vim.trim(output or "")
  if text == "" or text:find("=== ARTIKEL ===", 1, true)
    or text:find("## Editieversies", 1, true)
  then
    return nil
  end
  local lines = vim.split(text, "\n", { plain = true })
  while #lines > 0 and vim.trim(lines[1]) == "" do table.remove(lines, 1) end
  while #lines > 0 and vim.trim(lines[#lines]) == "" do table.remove(lines) end
  if #lines < 3 then return nil end
  lines[1] = lines[1]:gsub("^#+%s*", "")
  for _, line in ipairs(lines) do
    if line:match("^##+ %S") then return nil end
  end
  local rendered = table.concat(lines, "\n")
  if not rendered:find("**", 1, true) then return nil end
  return rendered
end

local function apply_edition_versions(buf, codes, names, variants, source, done)
  if not vim.api.nvim_buf_is_valid(buf) or #codes < 2 then
    if done then done(false) end
    return false
  end
  for _, code in ipairs(codes) do
    if type(variants[code]) ~= "string" or vim.trim(variants[code]) == "" then
      if done then done(false) end
      return false
    end
  end
  edition_review.create_workspace(buf, source, codes, names, variants, done)
  return true
end

M._edition_versions_confirm = function(codes, names)
  return vim.fn.confirm(
    "Dit artikel gaat naar meerdere kranten:\n\n"
      .. edition_names(codes, names)
      .. "\n\nVoor iedere krant een eigen versie maken?",
    "&Ja, aparte versies\n&Nee, gezamenlijke versie",
    2
  )
end

M._edition_versions_regenerate_confirm = function()
  return vim.fn.confirm(
    "Dit artikel bevat al aparte krantversies. <leader>ar vervangt deze allemaal. Doorgaan?",
    "&Vervangen\n&Annuleren",
    2
  )
end

M._edition_variant_runner = function(buf, code, source, done)
  ai_system(
    { aitext, "krantversie", "--edition", code },
    { text = true, stdin = source },
    function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        done(false, nil, vim.trim(result.stderr or ""))
        return
      end
      local variant = normalized_edition_variant(result.stdout)
      if not variant then
        done(false, nil, "AI-uitvoer heeft geen geldige kop, intro en body")
        return
      end
      done(true, variant, nil)
    end)
    end,
    "AI · Krantversie " .. code,
    buf
  )
end

local function offer_and_generate_edition_versions(buf, source, codes, names)
  if type(codes) ~= "table" or #codes < 2 then return end
  if M._edition_versions_confirm(codes, names) ~= 1 then
    notify_workflow("Eén gezamenlijke artikelversie behouden.", vim.log.levels.INFO)
    return
  end

  local variants, errors = {}, {}
  local remaining = #codes
  for _, code in ipairs(codes) do
    M._edition_variant_runner(buf, code, source, function(ok, variant, err)
      if ok then
        variants[code] = variant
      else
        table.insert(errors, code .. (err and (": " .. err) or ""))
      end
      remaining = remaining - 1
      if remaining ~= 0 then return end
      if #errors > 0 then
        notify_workflow(
          "Aparte krantversies niet toegepast; mislukt voor "
            .. table.concat(errors, "; ") .. ". De gezamenlijke versie blijft staan.",
          vim.log.levels.ERROR
        )
        return
      end
      if not apply_edition_versions(buf, codes, names, variants, source, function(applied)
        if not applied then
          notify_workflow(
            "Aparte krantversies konden niet veilig worden ingevoegd.",
            vim.log.levels.ERROR
          )
        end
      end) then
        notify_workflow("Aparte krantversies konden niet veilig worden ingevoegd.", vim.log.levels.ERROR)
      end
    end)
  end
end

M._same_edition_codes = same_edition_codes
M._set_edition_codes = set_edition_codes
M._reconcile_editions_after_rewrite = reconcile_editions_after_rewrite
M._edition_autodetect = edition_autodetect
M._drop_edition_versions_block = drop_edition_versions_block
M._normalized_edition_variant = normalized_edition_variant
M._apply_edition_versions = apply_edition_versions
M._offer_and_generate_edition_versions = offer_and_generate_edition_versions
M._edition_review = edition_review

function M.rewrite_article_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Eén canonieke split: frontmatter, tagblok, grens en staartsecties blijven
  -- buiten de AI-input en worden na de rewrite deterministisch teruggezet.
  local saved_fm, saved_ctrl, body_lines, saved_sections, saved_boundary =
    split_article_parts(lines)
  if has_edition_versions_block(saved_sections) then
    if M._edition_versions_regenerate_confirm() ~= 1 then
      notify_workflow("Herschrijven geannuleerd; bestaande krantversies zijn behouden.", vim.log.levels.INFO)
      return
    end
    saved_sections = drop_edition_versions_block(saved_sections)
  end
  local original_for_edition_detection = table.concat(
    reassemble_article(saved_fm, saved_ctrl, body_lines, {}, saved_boundary),
    "\n"
  )

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
      final_sections = drop_edition_versions_block(final_sections)
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
      mark_ai_rewrite_completed(buf)
      -- Een eerdere reviewworkspace is door deze expliciet bevestigde rewrite
      -- vervangen. Oude scratchbuffers mogen daarna niet meer terugschrijven.
      edition_review.close(buf, true)
      vim.b[buf].cached_metadata = nil
      vim.b[buf].cached_calendar_metadata = nil
      vim.b[buf].cached_facebook_text = nil

      -- Herken opnieuw op basis van de herschreven tekst. Een zichtbare
      -- e:-keuze blijft stil leidend zolang de betrouwbare inhoudsdetectie
      -- door de rewrite niet is veranderd.
      reconcile_editions_after_rewrite(
        buf,
        rewritten_str,
        original_for_edition_detection,
        function(ok, codes, names)
          if ok then
            offer_and_generate_edition_versions(buf, rewritten_body_str, codes, names)
          end
        end
      )

      -- Agenda-schakelaar (agenda:/cal:/calendar:) + facebook: x lezen.
      local agenda = _agenda_mode_from_lines(final_ctrl)
      local needs_calendar = agenda == "on"
      local agenda_denied = agenda == "off"
      local needs_facebook = false
      for _, line in ipairs(final_ctrl) do
        local k, v = line:match("^(%a[%a%d_]*)%s*:%s*(.-)%s*$")
        if k and v then
          k = k:lower(); v = v:lower()
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
      if not needs_calendar and not agenda_denied and not already_has_calendar_section
         and not vim.b[buf].calendar_ai_started
         and not vim.b[buf].calendar_autodetect_suppressed then
        local cal_score = _calendar_signal_score(rewritten_body_str)
        if cal_score >= _CALENDAR_THRESHOLD then
          notify_workflow(
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
            if (key == "recurrence_days" or key == "missing_event_fields")
                and val == "" then
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
  -- Een incomplete maar echte kandidaat moet juist zichtbaar zijn zodat de
  -- redacteur alleen de ontbrekende velden kan aanvullen. Voorheen verdween
  -- ieder enkelvoudig item met calendar_ready=false volledig en leek de
  -- herkenning ten onrechte mislukt. Een echte niet-kandidaat blijft verborgen.
  if not is_multiple
      and f.calendar_ready ~= "true"
      and f.event_candidate ~= "true" then
    return nil
  end
  if is_multiple and #items == 0 then return nil end

  local section = { "", "---", "", "## Kalender", "" }
  local function add(target, label, val)
    if val and val ~= "" then
      table.insert(target, label .. ": " .. val)
    end
  end

  local missing_hints = {
    calendar_title = "Titel (`Titel: ...`)",
    event_date = "Datum (`Datum: YYYY-MM-DD`, bijvoorbeeld `Datum: 2026-09-03`)",
    start_time = "Tijd (`Tijd: HH:MM`, bijvoorbeeld `Tijd: 10:00`)",
    location_name = "Locatie (`Locatie: ...`)",
    city = "Stad (`Stad: ...`)",
    calendar_body = "agendatekst (na een lege regel onder de velden)",
  }

  local function add_missing_hint(target, missing)
    if type(missing) == "string" then missing = { missing } end
    if type(missing) ~= "table" or #missing == 0 then return end
    local rendered = {}
    for _, field in ipairs(missing) do
      table.insert(rendered, missing_hints[field] or field)
    end
    table.insert(target, "")
    table.insert(target, "<!-- Ontbreekt: " .. table.concat(rendered, "; ") .. " -->")
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

    if item.calendar_ready ~= "true" and item.missing_event_fields then
      add_missing_hint(target, item.missing_event_fields)
    end
    if item.calendar_body and item.calendar_body ~= "" then
      table.insert(target, "")
      table.insert(target, item.calendar_body)
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

M._build_calendar_section_lines = build_calendar_section_lines

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
    notify_workflow("Kalenderanalyse loopt al voor dit artikel.", vim.log.levels.INFO)
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
        notify_workflow(
          "Kalenderdata toegevoegd. Controleer en pas aan, dan <leader>aw. "
            .. "Niet gewenst? <leader>aC weigert.",
          vim.log.levels.INFO,
          { ttl = 10 }
        )
      else
        notify_workflow("Geen kalenderitem gedetecteerd in de tekst.", vim.log.levels.WARN)
      end
    end)
  end, "AI · Kalender", buf)
end

function M.articlemeta_calendar_buffer()
  _run_articlemeta_calendar(vim.api.nvim_get_current_buf())
end

-- Weiger het voorgestelde agenda-item: verwijder de ## Kalender-sectie, wis de
-- gecachte kalenderdata en zet 'agenda: nee' als controleregel. Die persisteert
-- via articlemeta → calendar_disabled → de send-backstop, dus ook als je het
-- vergeet plaatst <leader>aw geen agenda-item. Web en print lopen door.
function M.reject_calendar(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = strip_calendar_section(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  local _, body_start = split_frontmatter_lines(lines)

  -- Verwijder bestaande agenda-/cal-controleregels in het leidende controleblok
  -- (voorkomt tegenstrijdigheid met een eerdere 'agenda: ja'/'cal: x').
  local out = {}
  local in_control_zone = true
  for i, line in ipairs(lines) do
    local keep = true
    if i >= body_start and in_control_zone then
      local t = vim.trim(line)
      if t == "" or t == ARTICLE_BOUNDARY then
        in_control_zone = false
      else
        local k = t:match("^(%a[%a%d_]*)%s*:")
        if k then
          k = k:lower()
          if k == "agenda" or k == "cal" or k == "calendar" then keep = false end
        else
          in_control_zone = false
        end
      end
    end
    if keep then table.insert(out, line) end
  end

  table.insert(out, body_start, "agenda: nee")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.b[buf].cached_calendar_metadata = nil
  vim.b[buf].calendar_ai_started = true
  notify_workflow(
    "Agenda-item geweigerd (agenda: nee). Web en print gaan gewoon door.",
    vim.log.levels.INFO
  )
end

-- Bereid een zelf getikt artikel voor op verzending ZONDER het te herschrijven:
-- plaats de === ARTIKEL ===-grens, vul de editie-regel (dateline → e:) + het
-- redactie-adres, en genereer de metadata (werktitel etc.) via articlemeta.
-- Daarna is <leader>aw op de gewone manier te draaien. Voor een agenda-item:
-- gebruik daarnaast <leader>ac.
function M.prepare_article(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if (vim.b[buf].pending_jobs or 0) > 0 then
    notify_workflow("Er lopen nog achtergrondtaken; even wachten.", vim.log.levels.INFO)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) == "" then
    vim.notify("Buffer is leeg.", vim.log.levels.WARN)
    return
  end

  -- 1. Grens plaatsen als die ontbreekt.
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  if not has_boundary then
    vim.api.nvim_buf_set_lines(
      buf, 0, -1, false, reassemble_article(fm, ctrl, body, sections, true)
    )
  end

  -- 2. Editie-regel (dateline → e:) + redactie-adres.
  local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  fill_detected_editions_line(buf, content, function(ok)
    if not ok then
      notify_workflow(
        "Editie bepalen mislukt — controleer de dateline (PLAATS - …) en de "
          .. "=== ARTIKEL ===-grens.",
        vim.log.levels.WARN
      )
    end

    -- 3. Metadata (werktitel etc.) via articlemeta — geen rewrite van de tekst.
    local input = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    ai_system({ articlemeta }, { text = true, stdin = input }, function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          vim.notify("Metadata ophalen mislukt: " .. (res.stderr or ""), vim.log.levels.ERROR)
          return
        end
        local meta_lines = vim.split(res.stdout, "\n", { plain = true })
        local new_fm = split_frontmatter_lines(meta_lines)
        if #new_fm > 0 then vim.b[buf].cached_metadata = new_fm end
        notify_workflow(
          "Artikel voorbereid — verzend met <leader>aw. (Agenda nodig? <leader>ac)"
        )
      end)
    end, "AI · Metadata", buf)
  end)
end

-- Eén centrale importherkenning leest de buffer eenmaal en verdeelt daarna
-- alleen de acties. De scoremodule zelf doet geen I/O, subprocess of AI.
local function _calendar_autodetect(buf, lines, text, evaluation, after_prompt)
  if vim.b[buf].calendar_autodetect_done then return end
  vim.b[buf].calendar_autodetect_done = true
  if vim.b[buf].calendar_ai_running then return end

  lines = lines or vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  text = text or table.concat(lines, "\n")

  -- Een reeds voorbereide papieren agendapagina is per definitie geen
  -- website-agenda-item. Dit beschermt ook opnieuw geopende concepten.
  if text:find("=== AGENDAPAGINA ===", 1, true) then return end
  if text:find("\n## Kalender", 1, true) or text:match("^## Kalender") then return end
  if text:find("calendar_article_id:") and not text:find("calendar_article_id:%s*null") then return end
  local agenda_mode = _agenda_mode_from_lines(lines)
  if agenda_mode == "off" then return end

  local detected = evaluation and evaluation.by_id and evaluation.by_id.calendar
  local score = detected and detected.points or _calendar_signal_score(text)
  if score >= _CALENDAR_THRESHOLD then
    local date_count = article_recognition.calendar_date_count(text)
    if agenda_mode == "auto" and date_count > 3 then
      vim.b[buf].calendar_autodetect_prompt_pending = true
      local choice = M._calendar_date_confirm(date_count)
      if not vim.api.nvim_buf_is_valid(buf) then return true end
      vim.b[buf].calendar_autodetect_prompt_pending = false
      if choice == 1 then
        notify_workflow(
          string.format("Kalenderdetectie bevestigd (score %d).", score),
          vim.log.levels.INFO
        )
        _run_articlemeta_calendar(buf)
      elseif choice == 2 then
        M.reject_calendar(buf)
      else
        -- Escape sluit alleen automatische detectie voor deze buffer uit.
        -- Handmatig <leader>ac blijft beschikbaar.
        vim.b[buf].calendar_autodetect_suppressed = true
        notify_workflow(
          "Kalenderdetectie overgeslagen. Handmatig starten kan met <leader>ac.",
          vim.log.levels.INFO
        )
      end
      if after_prompt then after_prompt() end
      return true
    end
    notify_workflow(
      string.format("Kalenderdetectie (score %d) — kalendermetadata wordt opgehaald.", score),
      vim.log.levels.INFO
    )
    _run_articlemeta_calendar(buf)
  end
end

-- Een afwijzing is een expliciete bufferbeslissing en mag later in dezelfde
-- workflow niet door een tweede detector worden genegeerd.
_offer_112_template = function(buf, score, context)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf]._112_rejected or vim.b[buf]._112_prompt_pending then return end

  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  if text:find("rubriek:%s*112") then return end
  if text:find("^112:") or text:find("^112%s+[^:]+:") then return end

  vim.b[buf]._112_prompt_pending = true
  local confidence = article_recognition.evaluate(text).by_id["112"].confidence
  local suffix = context and (" — " .. context) or ""
  local choice = M._112_confirm(
    string.format("112-bericht behandelen? (score %d)%s", score, suffix)
  )
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.b[buf]._112_prompt_pending = false
  if choice == 2 then
    vim.b[buf]._112_rejected = true
    notify_workflow("112-detectie afgewezen voor dit artikel.", vim.log.levels.INFO)
    return
  end
  if choice == 1 then
    vim.b[buf]._112_rejected = false
    if require("krant").apply_template_by_name("112 nieuws", {}, buf) then
      vim.b[buf].recognized_rubric = "112"
      vim.b[buf].recognized_rubric_score = confidence
    end
  end
end

local function apply_recognized_rubric(buf, candidate)
  if candidate.id == "112" then
    vim.b[buf]._112_rejected = false
    local ok = require("krant").apply_template_by_name("112 nieuws", {}, buf)
    if ok then
      vim.b[buf].recognized_rubric = candidate.id
      vim.b[buf].recognized_rubric_score = candidate.confidence
    end
    return ok
  end
  local ok, reason = require("krant").apply_detected_rubric(candidate.id, buf)
  if ok then
    vim.b[buf].recognized_rubric = candidate.id
    vim.b[buf].recognized_rubric_score = candidate.confidence
    vim.b[buf].rubric_recognition_pending = nil
  else
    vim.b[buf].rubric_recognition_pending = candidate.id .. ":" .. tostring(reason)
  end
  return ok
end

local function offer_rubric_candidates(buf, decision)
  if #decision.candidates == 1 and decision.candidate.id == "112" then
    _offer_112_template(buf, decision.candidate.points, "bij import")
    return
  end
  if vim.b[buf].rubric_recognition_prompt_pending then return end

  vim.b[buf].rubric_recognition_prompt_pending = true
  local choice = M._rubric_confirm(decision)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.b[buf].rubric_recognition_prompt_pending = false
  if not choice then
    for _, candidate in ipairs(decision.candidates) do
      if candidate.id == "112" then vim.b[buf]._112_rejected = true end
    end
    notify_workflow("Automatische rubriekherkenning niet toegepast.", vim.log.levels.INFO)
    return
  end
  apply_recognized_rubric(buf, choice)
end

local function rubric_autodetect(buf, text, evaluation)
  if vim.b[buf].rubric_recognition_done then return end
  vim.b[buf].rubric_recognition_done = true
  vim.b[buf]._112_autodetect_done = true
  if text:find("rubriek:%s*[%w_-]+") then return end

  local decision = article_recognition.rubric_decision(evaluation)
  if decision.action == "auto" then
    apply_recognized_rubric(buf, decision.candidate)
  elseif decision.action == "confirm" then
    offer_rubric_candidates(buf, decision)
  end
end

local function article_autodetect(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.b[buf].article_recognition_done then return end
  vim.b[buf].article_recognition_done = true
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if #lines == 0 then return end
  local text = table.concat(lines, "\n")
  edition_autodetect(buf, text)
  local evaluation = article_recognition.evaluate(text)
  -- Reeds toegepaste vaste templates hoeven niet opnieuw te worden toegepast,
  -- maar oudere buffers krijgen hier wel hun inmiddels vaste editiecode.
  local existing_rubric = article_recognition.rubric_decision(evaluation).existing
  if existing_rubric then
    require("krant").ensure_detected_rubric_edition(existing_rubric.id, buf)
    vim.b[buf].recognized_rubric = existing_rubric.id
    vim.b[buf].recognized_rubric_score = existing_rubric.confidence
  end
  local calendar_prompted = _calendar_autodetect(buf, lines, text, evaluation, function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local current_text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    rubric_autodetect(buf, current_text, article_recognition.evaluate(current_text))
  end)
	-- Automatische bevestigingen mogen elkaar niet overlappen. Eventuele
	-- rubriekherkenning volgt daarom pas na de datumbevestiging.
  if not calendar_prompted then rubric_autodetect(buf, text, evaluation) end
end

-- Inspecteerbare testpunten; productie gebruikt dezelfde lokale functies.
M._offer_112_template = _offer_112_template
M._article_autodetect = article_autodetect
M._calendar_autodetect = _calendar_autodetect

-- Een vers gestart Neovim 0.12-proces laadt de eerste buffer in de embedded
-- server voordat de TUI-client is gekoppeld. Een interactieve bevestiging in
-- dat korte venster kan de server laten vastlopen. Wacht daarom op UIEnter; bij een al
-- zichtbare Neovim-sessie (zoals een pv --remote) volstaat een korte defer.
local function schedule_article_autodetect(buf)
  capture_import_baseline(buf)
  local function run()
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then article_autodetect(buf) end
    end, 50)
  end

  if #vim.api.nvim_list_uis() > 0 then
    run()
    return "scheduled"
  end

  vim.api.nvim_create_autocmd("UIEnter", {
    once = true,
    desc = "Texttools importherkenning na TUI-koppeling",
    callback = run,
  })
  return "waiting_for_ui"
end

M._schedule_article_autodetect = schedule_article_autodetect

vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = import_patterns,
  callback = function(ev) schedule_article_autodetect(ev.buf) end,
})
vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Kalendergegevens maken en ter controle tonen",
})

vim.keymap.set("n", "<leader>aC", M.reject_calendar, {
  desc = "Voorgesteld agenda-item weigeren (agenda: nee)",
})

vim.keymap.set("n", "<leader>av", M.prepare_article, {
  desc = "Zelf getikt artikel voorbereiden voor verzending (geen rewrite)",
})

-- Lokale upvalue voor de eventvoorbereiding. De verzendflow gebruikt bewust
-- niet M._event_prepare: bij het opnieuw sourcen van deze module kan een oude
-- moduletabel nog in een callback leven. De lokale closure blijft na volledige
-- moduleload aan precies de bijbehorende implementatie gekoppeld.
local event_prepare

M._edition_send_confirm = function(resolved)
  local destination = edition_names(resolved.editions, resolved.names)
  local source = type(resolved.source) == "string"
      and resolved.source
    or "automatische detectie"
  local prompt
  if source:match("^standaard") then
    prompt = "Geen betrouwbare editie gevonden. Toch naar " .. destination .. "?"
  else
    prompt = "Bestemming automatisch bepaald: " .. destination
      .. " (" .. source .. "). Klopt dit?"
  end
  return vim.fn.confirm(
    prompt,
    "&Ja, vastleggen en doorgaan\n&Zelf e: invullen\n&Annuleren",
    1
  )
end

-- Een dateline of betrouwbare regiodetectie is gezaghebbend; die hoort niet
-- opnieuw bevestigd te worden maar stil als e:-regel te worden vastgelegd.
-- Geeft de detectie terug die daarvoor gebruikt mag worden.
local function edition_send_autorecord(resolved)
  if type(resolved) ~= "table" or resolved.has_explicit_editions == true then
    return nil
  end
  return high_confidence_detection(resolved)
end

M._edition_send_autorecord = edition_send_autorecord

-- Blokkerend bevestigen blijft verplicht wanneer niets het artikel ergens
-- plaatst: de stille De-Brug-default mag nooit ongevraagd naar Pubble.
local function needs_edition_send_confirmation(resolved)
  return type(resolved) == "table"
    and resolved.has_explicit_editions ~= true
    and edition_send_autorecord(resolved) == nil
end

M._needs_edition_send_confirmation = needs_edition_send_confirmation

local function path_is_in_directory(path, directory, recursive)
  local candidate = normalized_path(path)
  local parent = normalized_path(directory):gsub("/+$", "")
  if candidate == "" or parent == "" then return false end
  if recursive then return vim.startswith(candidate, parent .. "/") end
  return normalized_path(vim.fn.fnamemodify(candidate, ":h")):gsub("/+$", "") == parent
end

-- Alleen door pv beheerde werkbestanden worden na publicatie verwijderd.
-- Een willekeurig elders geopend Markdownbestand blijft altijd eigendom van de
-- gebruiker. Desktop geldt alleen nog als directe legacy-importmap; een
-- direct Inboxbestand is een expliciet geopend transactioneel herstelbestand.
local function is_managed_import_path(path)
  return path_is_in_directory(path, texttools_paths.work(), true)
      or path_is_in_directory(path, vim.fn.expand("~/Desktop"), false)
      or path_is_in_directory(path, texttools_paths.inbox(), false)
end
M._is_managed_import_path = is_managed_import_path

M._delete_source_file = function(path) return vim.fn.delete(path) end

local function add_sent_marker(buf, marker_block)
  local buf_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if buf_lines[1] and buf_lines[1]:match("^%*%*Verstuurd naar Pubble op ") then
    local replace_to = 1
    if buf_lines[2] and buf_lines[2]:match("^https?://") then replace_to = 2 end
    vim.api.nvim_buf_set_lines(buf, 0, replace_to, false, marker_block)
    return
  end

  local prepend = {}
  for _, line in ipairs(marker_block) do table.insert(prepend, line) end
  table.insert(prepend, "")
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, prepend)
end

-- Verwijder een beheerde pv-bron en verander de zichtbare tekst daarna in een
-- niet-opslagbare nacontrolebuffer. Daardoor kan :w of :wq het verwijderde
-- werkbestand niet opnieuw aanmaken. Niet-beheerde bestanden krijgen alleen de
-- verzendmarker en blijven gewone bestanden.
local function finalize_published_buffer(buf, file_path, marker_block, archive_path)
  add_sent_marker(buf, marker_block)

  if not is_managed_import_path(file_path) then return true, nil, false end

  local cleanup_ok = true
  local cleanup_error
  if vim.fn.filereadable(file_path) == 1 and M._delete_source_file(file_path) ~= 0 then
    cleanup_ok = false
    cleanup_error = "Werkbestand kon niet worden verwijderd: " .. file_path
  end

  vim.b[buf].published_archive_path = archive_path
  local display_name = vim.fn.fnamemodify(file_path, ":t")
  pcall(
    vim.api.nvim_buf_set_name,
    buf,
    ("pubble-nacontrole://%s/%d"):format(display_name ~= "" and display_name or "artikel.md", buf)
  )
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modified = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].readonly = true
  vim.bo[buf].modifiable = false

  return cleanup_ok, cleanup_error, true
end
M._finalize_published_buffer = finalize_published_buffer

function M.pubble_send(target_buf)
  local buf = target_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local agenda_page = require("agenda_page")
  if agenda_page.is_prepared(buf) then
    agenda_page.send(buf)
    return
  end
  if vim.b[buf].publication_in_progress then
    notify_workflow("Deze publicatierun is al bezig.", vim.log.levels.INFO)
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
      notify_workflow(
        "Verzenden start automatisch zodra de achtergrondtaken klaar zijn.",
        vim.log.levels.INFO
      )
    end
    return
  end

  -- Een gekozen rubriek mag pas naar externe systemen wanneer alle zichtbare
  -- templatevelden zijn ingevuld. Dit is een lokale preflight, dus vóór iedere
  -- Pubble-, media- of archiefwrite.
  local layout_valid, layout_error = layout_export.validate(buf)
  if not layout_valid then
    vim.notify(layout_error, vim.log.levels.ERROR)
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
  if not confirm_send_safeguard(buf, lines) then return end

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
  local has_linkedin = false
  for _, line in ipairs(lines) do
    if line:match("^## Kalender") then has_calendar = true end
    if line:match("^## Facebook") then has_facebook = true end
    if line:match("^## LinkedIn") then has_linkedin = true end
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

  local function same_edition_codes(left, right)
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
      return false
    end
    for i, code in ipairs(left) do
      if code ~= right[i] then return false end
    end
    return true
  end

  -- Handel redactionele koppelopdrachten één voor één af. Geen enkele mutatie
  -- gebeurt zonder Ja-keuze; na afhandeling worden alleen de opdrachtregels
  -- verwijderd en start dezelfde publicatieflow opnieuw met verse regels.
  local function process_publication_link_actions(actions)
    if type(actions) ~= "table" or #actions == 0 then return false end

    local index = 1
    local removed_link = false
    local function finish_and_restart()
      strip_leading_control_keys(buf, {
        koppel = true,
        ontkoppel = true,
        suggestiereden = true,
      })
      discard_unpublished_temp()
      if removed_link then
        local refreshed_content = table.concat(
          vim.api.nvim_buf_get_lines(buf, 0, -1, false),
          "\n"
        )
        fill_editions_line(buf, refreshed_content, function(ok)
          if ok then
            vim.schedule(function() M.pubble_send(buf) end)
          else
            vim.notify(
              "Koppeling is verwijderd, maar de suggestieregel kon niet worden vernieuwd. "
                .. "Controleer e: en druk opnieuw <leader>aw.",
              vim.log.levels.WARN
            )
          end
        end)
      else
        vim.schedule(function() M.pubble_send(buf) end)
      end
    end

    local function run_next()
      local action = actions[index]
      if type(action) ~= "table" then
        index = index + 1
        if index > #actions then finish_and_restart() else run_next() end
        return
      end

      local keyword = tostring(action.keyword or "")
      local names = type(action.names) == "table" and action.names or {}
      local target = table.concat(names, " + ")

      if action.action == "set"
          and same_edition_codes(action.current_editions, action.editions) then
        notify_workflow(
          "Koppeling ‘" .. keyword .. "’ bestond al voor " .. target .. ".",
          vim.log.levels.INFO
        )
        index = index + 1
        if index > #actions then finish_and_restart() else run_next() end
        return
      end
      if action.action == "remove" and action.exists ~= true then
        notify_workflow(
          "Geen koppeling gevonden voor ‘" .. keyword .. "’.",
          vim.log.levels.INFO
        )
        index = index + 1
        if index > #actions then finish_and_restart() else run_next() end
        return
      end

      local prompt
      if action.action == "set" then
        local current_names = type(action.current_names) == "table" and action.current_names or {}
        if #current_names > 0 then
          prompt = "Koppeling wijzigen: ‘" .. keyword .. "’ van "
            .. table.concat(current_names, " + ") .. " naar " .. target .. "?"
        else
          prompt = "Koppeling opslaan: ‘" .. keyword .. "’ → " .. target .. "?"
        end
      else
        prompt = "Koppeling verwijderen: ‘" .. keyword .. "’ → " .. target .. "?"
      end

      vim.ui.select({ "Ja", "Nee" }, { prompt = prompt }, function(choice)
        if choice == nil then
          discard_unpublished_temp()
          notify_workflow(
            "Verzending geannuleerd; koppelopdracht is blijven staan.",
            vim.log.levels.INFO
          )
          return
        end
        if choice == "Nee" then
          index = index + 1
          if index > #actions then finish_and_restart() else run_next() end
          return
        end

        local command = {
          texttools_python,
          "-m",
          publication_links_module,
          "--json",
        }
        if action.action == "set" then
          vim.list_extend(command, {
            "set",
            keyword,
            "--editions",
            table.concat(action.editions or {}, ", "),
            "--replace",
          })
        else
          vim.list_extend(command, { "remove", keyword })
        end

        vim.system(command, { text = true }, function(result)
          vim.schedule(function()
            if result.code ~= 0 then
              discard_unpublished_temp()
              local err = vim.trim(result.stderr or result.stdout or "")
              vim.notify(
                "Koppeling wijzigen mislukt" .. (err ~= "" and (": " .. err) or "")
                  .. ". Verzending is afgebroken; de opdracht is blijven staan.",
                vim.log.levels.ERROR
              )
              return
            end
            if action.action == "set" then
              notify_workflow("Koppeling opgeslagen: ‘" .. keyword .. "’ → " .. target .. ".")
            else
              removed_link = true
              notify_workflow("Koppeling verwijderd: ‘" .. keyword .. "’.")
            end
            index = index + 1
            if index > #actions then finish_and_restart() else run_next() end
          end)
        end)
      end)
    end

    run_next()
    return true
  end

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
      "--result-json",
    }
    if skip_calendar then table.insert(cmd, "--without-calendar") end
    if next(display_dates) ~= nil then
      table.insert(cmd, "--display-dates")
      table.insert(cmd, vim.fn.json_encode(display_dates))
    end
    local function handle_send_result(result, event_checked, event_report)
      vim.schedule(function()
        local publication_status = publication_status_from_output(
          result.stdout,
          result.stderr
        )
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
          if has_linkedin then msg = msg .. " | LinkedIn" end
          if event_report then
            local event_count = #(event_report.geplaatst or {})
            local existing_count = #(event_report.overgeslagen or {})
            msg = msg .. " | " .. event_count .. " vervolgplaatsing(en)"
            if existing_count > 0 then msg = msg .. " (" .. existing_count .. " hervat)" end
          end
          local failed_labels = failed_publication_labels(publication_status)
          local message_level
          if publication_status and publication_status.outcome == "partial" and #failed_labels > 0 then
            msg = msg .. " | LET OP: " .. table.concat(failed_labels, " + ") .. " mislukt"
            message_level = vim.log.levels.WARN
          end

          -- Schrijf voor iedere rubriek precies één actuele vormgevingstekst.
          -- Bij een fout blijft het plan staan en hervat <leader>aw via het
          -- Pubble-tempbestand zonder dubbele artikelen.
          local export_path, export_error = layout_export.finalize(buf)
          if export_error then
            vim.b[buf].publication_in_progress = false
            vim.b[buf].failed_send_file = temp_file
            vim.notify(
              "Artikel is gepubliceerd, maar de vormgevingsexport mislukte: "
                .. export_error
                .. ". <leader>aw probeert alleen de ontbrekende stappen opnieuw.",
              vim.log.levels.ERROR
            )
            return
          end
          if export_path then msg = msg .. " | vormgeving" end
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

          local sent_marker = "**Verstuurd naar Pubble op " .. os.date("%d-%m-%Y %H:%M") .. "**"
          local marker_block = { sent_marker }
          if article_url then table.insert(marker_block, article_url) end
          local cleanup_ok, cleanup_error = finalize_published_buffer(
            buf,
            file_path,
            marker_block,
            archive_data.path
          )
          if not cleanup_ok then
            message_level = vim.log.levels.WARN
            msg = msg .. " | LET OP: werkbestand bleef staan"
            vim.notify(
              cleanup_error .. ". Het artikel is wel gepubliceerd en gearchiveerd; verwijder dit bestand handmatig.",
              vim.log.levels.WARN
            )
          end

          -- Het browsermoment is het eindsignaal: hoofdartikel, media,
          -- eventuele vervolgen en archivering zijn nu allemaal gereed.
          if article_url then
            open_published_url(article_url)
          end

          notify_workflow(msg, message_level)

          vim.b[buf].publication_in_progress = false

        else
          vim.b[buf].publication_in_progress = false
          local failed_labels = failed_publication_labels(publication_status)
          if publication_status and #failed_labels > 0 then
            local newspaper_ok = false
            local web_ok = false
            for _, phase in ipairs(publication_status.phases) do
              if phase.name == "newspaper" and phase.status == "succeeded" then
                newspaper_ok = true
              elseif phase.name == "web" and phase.status == "succeeded" then
                web_ok = true
              end
            end
            local prefix = newspaper_ok and web_ok
                and "Hoofdartikel is geplaatst, maar "
              or "Pubble-publicatie onvolledig: "
            vim.notify(
              prefix
                .. table.concat(failed_labels, " + ")
                .. " mislukt. <leader>aw hervat met de opgeslagen IDs.",
              vim.log.levels.ERROR
            )
          else
            local stderr = vim.trim(result.stderr or "")
            local stdout = vim.trim(result.stdout or "")
            local output = stderr ~= "" and stderr or stdout
            vim.notify(output ~= "" and output or "Pubble send mislukt", vim.log.levels.ERROR)
          end
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
            notify_workflow(
              "Genereren van evenementvervolgteksten geannuleerd.",
              vim.log.levels.INFO
            )
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
        notify_workflow(
          "Publicatievoorbereiding mislukt" .. (err ~= "" and (": " .. err) or "")
            .. " — verzending afgebroken.",
          vim.log.levels.ERROR
        )
        return
      end

      -- Ontbreekt de zichtbare e:-regel, dan legt een betrouwbare dateline- of
      -- regiodetectie zichzelf alsnog vast: die is gezaghebbend en hoort niet
      -- bevestigd te worden. Zo blijft e: de bron van waarheid, ook wanneer de
      -- invulling bij import of na herschrijven niet is gebeurd.
      local autorecord = edition_send_autorecord(resolved)
      if autorecord then
        if not set_edition_codes(buf, autorecord.editions) then
          discard_unpublished_temp()
          notify_workflow("Editiebestemming kon niet worden vastgelegd.", vim.log.levels.ERROR)
          return
        end
        ensure_detected_dateline(buf, autorecord)
        adapt_editorial_address(buf, autorecord.editions[1])
        discard_unpublished_temp()
        notify_workflow(
          "Bestemming vastgelegd: "
            .. edition_names(autorecord.editions, autorecord.names)
            .. " (" .. (autorecord.source or "automatische detectie") .. ")."
        )
        vim.schedule(function() M.pubble_send(buf) end)
        return
      end

      -- Zonder zichtbare e:-keuze én zonder betrouwbare detectie mag de stille
      -- De-Brug-default nooit naar Pubble. Na Ja leggen we de keuze in de
      -- buffer vast en starten we dezelfde flow opnieuw; daardoor wordt dit
      -- niet nogmaals gevraagd en blijft e: de bron van waarheid.
      if needs_edition_send_confirmation(resolved) then
        local choice = M._edition_send_confirm(resolved)
        if choice == 1 then
          if not set_edition_codes(buf, resolved.editions) then
            discard_unpublished_temp()
            notify_workflow("Editiebestemming kon niet worden vastgelegd.", vim.log.levels.ERROR)
            return
          end
          discard_unpublished_temp()
          vim.schedule(function() M.pubble_send(buf) end)
        elseif choice == 2 then
          discard_unpublished_temp()
          notify_workflow(
            "Vul boven === ARTIKEL === een e:-regel in en druk daarna opnieuw <leader>aw.",
            vim.log.levels.INFO
          )
        else
          discard_unpublished_temp()
          notify_workflow("Verzending geannuleerd.", vim.log.levels.INFO)
        end
        return
      end

      if process_publication_link_actions(resolved.link_actions) then
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
            notify_workflow("Verzending geannuleerd.", vim.log.levels.INFO)
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
      if #resolved.editions == 1 then
        local msg = "Artikel gaat naar: " .. table.concat(bestemming, " + ")
        if resolved.source then
          msg = msg .. "  (" .. resolved.source .. ")"
        end
        -- Via notify_workflow (fidget-toast) i.p.v. rauw vim.notify: een
        -- commandoregel-echo triggert anders de "Press ENTER"-prompt. Fidget
        -- toont een niet-blokkerende melding, dus de verzending loopt gewoon door.
        notify_workflow(msg)
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
        notify_workflow(
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
              notify_workflow("Verzending geannuleerd.", vim.log.levels.INFO)
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
            notify_workflow(
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
          notify_workflow("Verzending geannuleerd.", vim.log.levels.INFO)
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
-- De bron van waarheid staat in de gedeelde cloudmap en wordt uitsluitend via
-- teams-config gelezen/gemuteerd. Dit menu is puur de UI erop: waarneming uit
-- de gedeelde lijst kiezen, een nieuwe vervanger bewaren, terugzetten naar
-- de vaste eindredacteur, meldingen per editie uitzetten, of alles aan/uit.
-- ---------------------------------------------------------------------------

local function teams_config_command(args)
  local command = { teams_config_cli }
  vim.list_extend(command, args)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    vim.notify("Teams-config bijwerken mislukt: " .. vim.trim(output), vim.log.levels.ERROR)
    return nil
  end
  local ok, config = pcall(vim.json.decode, output)
  if not ok or type(config) ~= "table" or type(config.editions) ~= "table" then
    vim.notify("Teams-config gaf geen geldige JSON terug.", vim.log.levels.ERROR)
    return nil
  end
  return config
end

local function teams_read_config()
  return teams_config_command({ "show" })
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
      config = teams_config_command({ "set-enabled", aan and "off" or "on" })
      if not config then return end
      notify_workflow(
        "Teams-meldingen " .. (config.enabled and "AAN" or "UIT"),
        vim.log.levels.INFO
      )
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
      local args = { "set-recipient", choice.code }
      if email then
        vim.list_extend(args, { "--email", email })
      else
        table.insert(args, "--off")
      end
      config = teams_config_command(args)
      if not config then return end
      e = config.editions[choice.code]
      local nieuw = (e.email == vim.NIL) and "geen melding" or tostring(e.email or "geen melding")
      notify_workflow(
        string.format("%s → %s", e.krant or choice.code, nieuw),
        vim.log.levels.INFO
      )
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
            config = teams_config_command({
              "add-recipient", choice.code, "--name", name, "--email", email,
            })
            if not config then return end
            e = config.editions[choice.code]
            notify_workflow(
              string.format("%s → %s", e.krant or choice.code, tostring(e.email)),
              vim.log.levels.INFO
            )
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


local function tail_section_blocks(sections)
  local blocks, current = {}, nil
  local function finish_current()
    if not current then return end
    while #current > 1
      and (vim.trim(current[#current]) == "" or vim.trim(current[#current]) == "---") do
      table.remove(current)
    end
    table.insert(blocks, current)
    current = nil
  end

  for _, line in ipairs(sections) do
    if line:match("^## %S") then
      finish_current()
      current = { line }
    elseif current then
      table.insert(current, line)
    end
  end
  finish_current()
  return blocks
end

-- Vervang uitsluitend de gevraagde staartsectie. Facebook en LinkedIn kunnen
-- daardoor gelijktijdig terugkomen: iedere callback leest de actuele buffer
-- opnieuw, behoudt alle andere blokken en schrijft op de Neovim-mainthread.
local function upsert_tail_section(lines, title, content)
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  local heading = "## " .. title
  local blocks = tail_section_blocks(sections)

  for index = #blocks, 1, -1 do
    if vim.trim(blocks[index][1] or "") == heading then
      table.remove(blocks, index)
    end
  end

  local new_block = { heading, "" }
  local trimmed_content = vim.trim(content)
  if trimmed_content ~= "" then
    for _, line in ipairs(vim.split(trimmed_content, "\n", { plain = true })) do
      table.insert(new_block, line)
    end
  end

  local insert_at = #blocks + 1
  if title == "Facebook" then
    for index, block in ipairs(blocks) do
      if vim.trim(block[1] or "") == "## LinkedIn" then
        insert_at = index
        break
      end
    end
  elseif title == "LinkedIn" then
    for index, block in ipairs(blocks) do
      if vim.trim(block[1] or "") == "## Facebook" then
        insert_at = index + 1
        break
      end
    end
  end
  table.insert(blocks, insert_at, new_block)

  local rebuilt_sections = {}
  for block_index, block in ipairs(blocks) do
    if block_index > 1 then table.insert(rebuilt_sections, "") end
    for _, line in ipairs(block) do table.insert(rebuilt_sections, line) end
  end
  return reassemble_article(fm, ctrl, body, rebuilt_sections, has_boundary)
end

-- Klein headless testpunt voor het samenvoegen van gelijktijdige socialtaken.
M._upsert_tail_section = upsert_tail_section

local function generate_social_section(opts)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Alleen de kale artikelbody als AI-input — geen frontmatter, kopcodes of
  -- eerder gegenereerde secties (voorkomt dat bijv. "Fotograaf:" in de post lekt).
  local _, _, body = split_article_parts(lines)
  local article_text = table.concat(body, "\n")
  local prompt = opts.prompt
  if opts.prompt_112 and _112_signal_score(article_text) >= _112_THRESHOLD then
    prompt = opts.prompt_112
  end

  ai_system(
    { aitext, prompt },
    { text = true, stdin = article_text },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          local err = vim.trim(result.stderr or result.stdout or "")
          vim.notify(opts.title .. " AI mislukt: " .. (err ~= "" and err or "onbekende fout"), vim.log.levels.ERROR)
          return
        end

        local ai_output = vim.trim(result.stdout or "")
        if ai_output == "" then
          vim.notify(opts.title .. " AI gaf geen tekst terug.", vim.log.levels.WARN)
          return
        end

        -- Lees huidige bufferinhoud zodat tussentijdse bewerkingen én een andere
        -- socialtaak die eerder klaar was bewaard blijven.
        local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        local updated = upsert_tail_section(current_lines, opts.title, ai_output)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, updated)
        local character_count = vim.fn.strchars(ai_output)
        if opts.title == "LinkedIn" and character_count > 420 then
          vim.notify(
            "LinkedIn-tekst is " .. character_count
              .. " tekens; Pubble accepteert maximaal 420. Kort de sectie in vóór <leader>aw.",
            vim.log.levels.WARN
          )
        else
          notify_workflow(
            opts.title .. "-bericht toegevoegd. Pas aan indien nodig, dan <leader>aw.",
            vim.log.levels.INFO,
            { ttl = 10 }
          )
        end
      end)
    end,
    "AI · " .. opts.title,
    buf
  )
end

function M.generate_facebook()
  generate_social_section({
    title = "Facebook",
    prompt = "facebook_bericht",
    prompt_112 = "facebook_bericht_112",
  })
end

function M.generate_linkedin()
  generate_social_section({
    title = "LinkedIn",
    prompt = "linkedin_bericht",
  })
end

vim.keymap.set("n", "<leader>af", M.generate_facebook, {
  desc = "Facebooktekst genereren en ter controle tonen",
})

vim.keymap.set("n", "<leader>al", M.generate_linkedin, {
  desc = "LinkedIn-tekst genereren en ter controle tonen",
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

-- <leader>an — neutraliseer uitsluitend subjectieve journalistentaal. De
-- centrale prompt en Python-validatie bewaken minimale wijzigingen, citaten en
-- concrete waarden. Een laat resultaat mag nieuwere bufferbewerkingen nooit
-- overschrijven.
function M.journalistic_neutralize()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  local requested_tick = vim.api.nvim_buf_get_changedtick(buf)

  ai_system(
    { aitext, "journalistiek_neutraliseren" },
    { text = true, stdin = table.concat(body, "\n") },
    function(result)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        if vim.api.nvim_buf_get_changedtick(buf) ~= requested_tick then
          notify_workflow(
            "Neutraliteitsresultaat niet toegepast: de tekst is tijdens de AI-controle gewijzigd.",
            vim.log.levels.WARN,
            { ttl = 9 }
          )
          return
        end
        if result.code ~= 0 then
          local err = vim.trim(result.stderr or result.stdout or "")
          vim.notify(
            "Journalistiek neutraliseren mislukt: " .. (err ~= "" and err or "onbekende fout"),
            vim.log.levels.ERROR
          )
          return
        end

        local output = vim.trim(result.stdout or "")
        if output == "" then
          vim.notify("Neutraliteitscontrole gaf geen tekst terug.", vim.log.levels.ERROR)
          return
        end

        local new_body = vim.split(output, "\n", { plain = true })
        local new_lines = reassemble_article(fm, ctrl, new_body, sections, has_boundary)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
        mark_ai_neutrality_completed(buf, new_lines)
        notify_workflow(
          "Journalistieke neutraliteitscontrole klaar. Controleer de minimale wijzigingen; gebruik u om ongedaan te maken.",
          vim.log.levels.INFO,
          { ttl = 9 }
        )
      end)
    end,
    "AI · Journalistiek neutraliseren",
    buf
  )
end

vim.keymap.set("n", "<leader>an", M.journalistic_neutralize, {
  desc = "Journalistiek neutraliseren met minimale tekstwijzigingen",
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
local function insert_headings(body, koppen, paras, has_headline)
  table.sort(koppen, function(a, b) return a.n > b.n end)
  local out = {}
  for i, l in ipairs(body) do out[i] = l end
  local first_allowed = has_headline and 4 or 3
  for _, k in ipairs(koppen) do
    if k.n >= first_allowed and k.n <= #paras - 1 then
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
local function insert_streamer_midway(body, streamer_text, has_headline)
  local paras = scan_paragraphs(body)
  local prose = {}
  local first_prose = has_headline and 2 or 1
  for i = first_prose, #paras do
    -- De eerste prozaalinea is de lead; scan_paragraphs kan een vette lead
    -- technisch als heading markeren, maar inhoudelijk blijft dit tekst.
    if i == first_prose or not paras[i].heading then
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

-- Laat de Python-core bepalen of de eerste alinea een bestaande kop of de lead
-- is. Daardoor delen inspectie en plaatsing in alle clients exact dezelfde
-- deterministische regels.
local function inspect_article_headline(body)
  local result = vim.system(
    { article_headline, "inspect" },
    { text = true, stdin = table.concat(body, "\n") }
  ):wait(3000)
  local ok, inspection = pcall(vim.json.decode, result.stdout or "")
  if result.code ~= 0 or not ok or type(inspection) ~= "table" then
    local detail = vim.trim(result.stderr or "")
    vim.notify(
      "Kopstructuur kon niet worden gecontroleerd"
        .. (detail ~= "" and (": " .. detail) or "."),
      vim.log.levels.ERROR
    )
    return nil
  end
  return inspection
end

local function apply_selected_headline(body, kop)
  local result = vim.system(
    { article_headline, "apply", "--headline", kop },
    { text = true, stdin = table.concat(body, "\n") }
  ):wait(3000)
  if result.code ~= 0 or type(result.stdout) ~= "string" or result.stdout == "" then
    local detail = vim.trim(result.stderr or "")
    vim.notify(
      "Gekozen kop kon niet worden geplaatst"
        .. (detail ~= "" and (": " .. detail) or "."),
      vim.log.levels.ERROR
    )
    return nil
  end
  return vim.split((result.stdout:gsub("\n$", "")), "\n", { plain = true })
end

-- <leader>at — tussenkopjes + streamer + kopopties, als korte AI-calls.
-- De AI levert alleen kopjes-met-positie ("3: Kopje"), één streamerregel en
-- twee alternatieve koppen; de artikeltekst zelf wordt nooit door de AI
-- geregenereerd; alle invoeging is deterministisch. De streamer-call wordt
-- overgeslagen als er al een eigen >-streamer in de tekst staat — die eigen
-- streamer gaat dan als context mee naar de kopopties, want kop en streamer
-- moeten elkaar aanvullen. Uit de kopopties kies je via een menu; de huidige
-- kop behouden kan altijd.
function M.tussenkopjes_streamer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local fm, ctrl, body, sections, has_boundary = split_article_parts(lines)
  local headline = inspect_article_headline(body)
  if not headline then return end
  local has_headline = headline.has_headline == true
  local paras = scan_paragraphs(body)

  local existing_streamer = nil
  for _, l in ipairs(body) do
    local s = l:match("^>%s*(.+)$")
    if s then existing_streamer = vim.trim(s); break end
    if vim.trim(l) == ">" then existing_streamer = ""; break end
  end
  local has_streamer = existing_streamer ~= nil

  local body_text = table.concat(body, "\n")

  -- Genummerde variant voor de tussenkopjes-prompt: elke alinea krijgt een
  -- [N]-marker zodat de AI posities kan teruggeven i.p.v. de hele tekst.
  local numbered = {}
  for i, l in ipairs(body) do numbered[i] = l end
  for n, p in ipairs(paras) do
    numbered[p.s] = "[" .. n .. "] " .. numbered[p.s]
  end
  local headline_status = has_headline and "aanwezig" or "ontbreekt"
  local numbered_text = "Kopstatus: " .. headline_status .. "\n" .. table.concat(numbered, "\n")

  local results = { koppen = nil, streamer = nil, kopopties = nil }
  -- Slots: tussenkopjes + kopopties, plus de streamer-call als die nog moet.
  local pending = has_streamer and 2 or 3

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

    local new_body = insert_headings(body, koppen, paras, has_headline)
    if #koppen == 0 then
      notify_workflow(
        "Geen tussenkopjes toegevoegd (artikel te kort of AI gaf niets terug).",
        vim.log.levels.INFO
      )
    end

    if results.streamer and results.streamer ~= "" then
      local with_streamer = insert_streamer_midway(new_body, results.streamer, has_headline)
      if with_streamer then
        new_body = with_streamer
      else
        notify_workflow(
          "Artikel te kort voor een mid-tekst streamer — overgeslagen.",
          vim.log.levels.WARN
        )
      end
    end

    local function write_body(final_body)
      vim.api.nvim_buf_set_lines(
        buf, 0, -1, false,
        reassemble_article(fm, ctrl, final_body, sections, has_boundary)
      )
      if has_streamer then
        notify_workflow(
          "Tussenkopjes toegevoegd; eigen > streamer blijft staan.",
          vim.log.levels.INFO
        )
      end
    end

    -- Twee kopregels; nummering/bullets/vetmarkering van de AI wordt gestript.
    local kop_options = {}
    for _, l in ipairs(vim.split(results.kopopties or "", "\n", { plain = true })) do
      local kop = vim.trim(l):gsub("^%d+[%.:%)]%s*", ""):gsub("^[-*]%s+", "")
      kop = vim.trim(kop:gsub("^%*+", ""):gsub("%*+$", "")):gsub("%.$", "")
      if kop ~= "" and #kop_options < 2 then table.insert(kop_options, kop) end
    end

    if #kop_options == 0 then
      write_body(new_body)
      return
    end

    local keep_label = "Huidige kop behouden"
    local items = {}
    for _, kop in ipairs(kop_options) do table.insert(items, kop) end
    table.insert(items, keep_label)
    vim.ui.select(items, { prompt = "Kop kiezen (vult de streamer aan):" }, function(choice)
      if choice and choice ~= keep_label then
        local with_headline = apply_selected_headline(new_body, choice)
        if not with_headline then return end
        new_body = with_headline
      end
      write_body(new_body)
    end)
  end

  -- De kop moet de streamer aanvullen; deze call start daarom pas zodra de
  -- streamertekst bekend is (bestaand of net gegenereerd, eventueel leeg).
  local function launch_kopopties(streamer_text)
    local input = "Kopstatus: " .. headline_status .. "\n"
    if streamer_text and streamer_text ~= "" then
      input = input .. "Streamer: " .. streamer_text .. "\n"
    end
    input = input .. "\n" .. body_text
    ai_system(
      { aitext, "kopopties" },
      { text = true, stdin = input },
      function(result)
        vim.schedule(function()
          if result.code == 0 then
            results.kopopties = result.stdout
          else
            notify_workflow(
              "Kopopties genereren mislukt — huidige kop blijft staan.",
              vim.log.levels.WARN
            )
          end
          pending = pending - 1
          finish()
        end)
      end,
      "AI · Kopopties",
      buf
    )
  end

  if has_streamer then
    launch_kopopties(existing_streamer)
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
            notify_workflow(
              "Streamer genereren mislukt — alleen tussenkopjes toegepast.",
              vim.log.levels.WARN
            )
          end
          launch_kopopties(results.streamer)
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
  desc = "Tussenkopjes + streamer + 2 kopopties (streamer alleen als er nog geen > staat)",
})

M._inspect_article_headline = inspect_article_headline
M._apply_selected_headline = apply_selected_headline


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
        mark_ai_rewrite_completed(buf)
        notify_workflow("Klaar. Gebruik u om ongedaan te maken.", vim.log.levels.INFO)
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
        notify_workflow(
          "Antwoord toegevoegd. Typ *** met de volgende vraag en druk dan <leader>ag.",
          vim.log.levels.INFO,
          { ttl = 10 }
        )
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
local function show_rubric_recognition_help()
  notify_workflow(
    table.concat({
      "Deterministische herkenning: kalender, 112, Kamper Kiek en Hondenhoek.",
      "Kamper Kiek: vaste naam + nummering 1-3. Hondenhoek: Bert Nieuwenhuis + hond/honden (of Hondenhoek + tweede signaal).",
      "Alleen zekere Kamper Kiek/Hondenhoek wordt automatisch toegepast; 112 vraagt altijd bevestiging.",
      "Raadspraat, Ondernemen in Kampen en andere vaste rubrieken kies je zelf via <leader>kt.",
      "<leader>kp gebruikt alleen planning; namen en foto's worden pas na je keuze ingevuld.",
    }, "\n"),
    vim.log.levels.INFO,
    { ttl = 12 }
  )
end

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
      { label = "Naam aan gekozen edities koppelen", insert = "koppel: " },
      { label = "Bestaande naamkoppeling verwijderen", insert = "ontkoppel: " },
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
    label = "Rubrieken",
    prompt = "Rubrieken:",
    items = {
      { label = "Rubriektemplate handmatig kiezen (<leader>kt)", action = function() require("krant").menu() end },
      { label = "Planning Raadspraat/Ondernemen (<leader>kp)", action = function() vim.cmd("RubriekPlanning") end },
      { label = "Papieren agendapagina voorbereiden (<leader>ka)", action = function() require("agenda_page").prepare() end },
      { label = "Wat wordt automatisch herkend?", action = show_rubric_recognition_help },
    },
  },
  {
    label = "Publicatie-extra's",
    prompt = "Publicatie-extra invoegen:",
    items = {
      { label = "Rubriek 112", insert = "rubriek: 112" },
      { label = "Agenda: AI beslist (standaard, regel niet nodig)", insert = "agenda: auto" },
      { label = "Agenda: forceer agenda-item", insert = "agenda: ja" },
      { label = "Agenda: weigeren (geen agenda-item)", insert = "agenda: nee" },
      { label = "Agenda: kalenderitem nu maken (<leader>ac)", action = function() M.articlemeta_calendar_buffer() end },
      { label = "Agenda: voorgesteld item weigeren (<leader>aC)", action = function() M.reject_calendar() end },
      { label = "Facebooktekst door AI laten maken", insert = "facebook: x" },
      { label = "LinkedIn-tekst door AI laten maken", action = function() M.generate_linkedin() end },
      { label = "Eigen Facebooktekst schrijven", action = function() M.edit_facebook_text() end },
      { label = "Eigen LinkedIn-tekst schrijven", action = function() M.edit_linkedin_text() end },
    },
  },
  {
    label = "Acties",
    prompt = "Actie starten:",
    items = {
      { label = "Artikel herschrijven (<leader>ar)", action = function() M.rewrite_article_buffer() end },
      { label = "Eigen artikel voorbereiden, geen rewrite (<leader>av)", action = function() M.prepare_article() end },
      { label = "Tekstcheck (<leader>ao)", action = function() M.tekstcheck() end },
      { label = "Journalistiek neutraliseren (<leader>an)", action = function() M.journalistic_neutralize() end },
      { label = "Tussenkopjes en streamer (<leader>at)", action = function() M.tussenkopjes_streamer() end },
      { label = "LinkedIn-tekst maken (<leader>al)", action = function() M.generate_linkedin() end },
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

local function edit_social_text(title)
  local buf = vim.api.nvim_get_current_buf()
  if title == "Facebook" then
    strip_leading_control_line(buf, "^[Ff]acebook%s*:%s*x%s*$")
    strip_leading_control_line(buf, "^[Ff]acebook_tekst%s*:")
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for index, line in ipairs(lines) do
    if vim.trim(line) == "## " .. title then
      local line_after = index + 1
      if lines[line_after] == nil or lines[line_after] ~= "" then
        vim.api.nvim_buf_set_lines(0, index, index, false, { "" })
      end
      vim.api.nvim_win_set_cursor(0, { line_after, 0 })
      vim.cmd("startinsert!")
      return
    end
  end

  local updated = upsert_tail_section(lines, title, "")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, updated)
  for index, line in ipairs(updated) do
    if vim.trim(line) == "## " .. title then
      vim.api.nvim_win_set_cursor(0, { index + 1, 0 })
      vim.cmd("startinsert!")
      return
    end
  end
end

function M.edit_facebook_text()
  edit_social_text("Facebook")
end

function M.edit_linkedin_text()
  edit_social_text("LinkedIn")
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
