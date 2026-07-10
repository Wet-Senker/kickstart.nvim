local M = {}

-- Maak Pubble Inbox mappenstructuur aan als Keyboard Maestro een paste-bestand opent.
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = vim.fn.expand("~/Desktop") .. "/*.md",
  callback = function()
    local inbox = vim.fn.expand("~/Desktop/Pubble Inbox")
    vim.fn.mkdir(inbox .. "/articles", "p")
    vim.fn.mkdir(inbox .. "/used", "p")
  end,
})

-- Wrap vim.system with a fidget progress handle so the user sees a spinner
-- while any AI call is running.
local function ai_system(cmd, opts, callback, title, message)
  local handle = require("fidget.progress").handle.create {
    title   = title or "AI",
    message = message or "bezig...",
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

local function run_on_buffer(prompt_name, append)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")
  local cmd = { aitext, prompt_name }
  if append then table.insert(cmd, "--append") end

  ai_system(cmd, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local new_lines = vim.split(result.stdout, "\n", { plain = true })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      else
        vim.notify("AI rewrite mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
      end
    end)
  end, prompt_name)
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

function M.rewrite_article_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Strip leading control lines BEFORE sending to AI so they are never lost or
  -- corrupted. We put them back at the top after the rewrite.
  local saved_ctrl, body_lines = extract_leading_control_lines(lines)
  local input = table.concat(body_lines, "\n")

  ai_system({ aitext, "journalistiek_schrijven" }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("AI rewrite mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return
      end

      local new_lines = vim.split(result.stdout, "\n", { plain = true })

      -- Lees de huidige bufferinhoud opnieuw: de gebruiker kan tijdens het wachten
      -- controleregels bovenaan hebben getypt. Die gaan voor op de pre-rewrite ctrl.
      local current_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local current_ctrl, _ = extract_leading_control_lines(current_lines)
      local final_ctrl = #current_ctrl > 0 and current_ctrl or saved_ctrl

      if #final_ctrl > 0 then
        local combined = {}
        for _, l in ipairs(final_ctrl) do table.insert(combined, l) end
        for _, l in ipairs(new_lines) do table.insert(combined, l) end
        new_lines = combined
      end

      local rewritten_str = table.concat(new_lines, "\n")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      vim.b[buf].cached_metadata = nil

      -- Metadata ophalen op de achtergrond en cachen in een buffervariabele.
      -- De buffer blijft schoon; bij leader aw wordt de cache geïnjecteerd.
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

function M.articlemeta_calendar_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local input = table.concat(lines, "\n")

  ai_system({ articlemeta, "--calendar" }, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify("articlemeta mislukt: " .. (result.stderr or ""), vim.log.levels.ERROR)
        return
      end

      local meta_lines = vim.split(result.stdout, "\n", { plain = true })

      -- Cache frontmatter zodat de buffer schoon blijft tot verzenden.
      local new_fm, _ = split_frontmatter_lines(meta_lines)
      if #new_fm > 0 then
        vim.b[buf].cached_metadata = new_fm
      end

      -- Bouw ## Kalender sectie uit de metadata-output.
      local section = build_calendar_section_lines(meta_lines)

      -- Werk met de huidige bufferinhoud zodat bewerkingen bewaard blijven.
      local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local base = strip_calendar_section(current)

      if section then
        for _, line in ipairs(section) do
          table.insert(base, line)
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, base)
        vim.notify("Kalenderdata toegevoegd. Controleer en pas aan, dan <leader>aw.", vim.log.levels.INFO)
      else
        vim.notify("Geen kalenderitem gedetecteerd in de tekst.", vim.log.levels.WARN)
      end
    end)
  end, "AI · Kalender")
end

vim.keymap.set("n", "<leader>am", M.articlemeta_buffer, {
  desc = "Add article metadata",
})

vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Add calendar article and metadata",
})


function M.pubble_send()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if vim.trim(table.concat(lines, "\n")) == "" then
    vim.notify("Huidig buffer is leeg", vim.log.levels.ERROR)
    return
  end

  -- Inject cached metadata (from background rewrite chain) if the buffer
  -- has no frontmatter yet. This keeps the buffer clean until send time.
  local cached_fm = vim.b[buf].cached_metadata
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
  for _, line in ipairs(lines) do
    local e = line:match("^editie:%s*(.+)$") or line:match("^%s*editions:%s*(.+)$")
    if e then
      local v = vim.trim(e)
      if v ~= "" and v ~= "null" then editie = v end
    end
    if line:match("^## Kalender") then has_calendar = true end
    if line:match("^## Facebook") then has_facebook = true end
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
  vim.fn.writefile(lines, temp_file)
  vim.notify("Verzenden naar Pubble...", vim.log.levels.INFO)

  ai_system(
    { pubble_send, temp_file, "--create", "--no-open", "--write-ids" },
    { text = true },
    function(result)
      vim.schedule(function()
        vim.fn.delete(temp_file)

        if result.code == 0 then
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
            -- Strip YAML frontmatter zodat het txt-bestand alleen artikeltekst bevat.
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
            vim.fn.writefile(export_lines, gn.dir .. '/' .. gn.txt_name)
            vim.b[buf].gn_export = nil
          end

          -- Schrijf opgeschoonde buffer naar Pubble Inbox/used/.
          -- Strip YAML frontmatter en controleregels; bewaar kop, body en Facebook.
          -- Verwijder het originele bestand op het bureaublad.
          local used_dir = inbox .. "/used"
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

          local filename = vim.fn.fnamemodify(stem .. ".md", ":t")
          local dest = used_dir .. "/" .. filename
          local counter = 1
          while vim.fn.filereadable(dest) == 1 do
            dest = used_dir .. "/" .. stem .. "-" .. counter .. ".md"
            counter = counter + 1
          end
          vim.fn.writefile(out, dest)

          -- Verwijder origineel op bureaublad; buffer blijft zichtbaar voor nacontrole.
          if file_path ~= "" and vim.fn.filereadable(file_path) == 1 then
            vim.fn.delete(file_path)
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

  ai_system(
    { aitext, "facebook_bericht" },
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
    "AI · Facebook"
  )
end

vim.keymap.set("n", "<leader>af", M.generate_facebook, {
  desc = "Generate Facebook post",
})


function M.opmaken()
  run_on_buffer("opmaken", false)
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
