local M = {}

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
  local cmd

  if append then
    cmd = "%!" .. shellescape(aitext) .. " " .. shellescape(prompt_name) .. " --append"
  else
    cmd = "%!" .. shellescape(aitext) .. " " .. shellescape(prompt_name)
  end

  vim.cmd(cmd)
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

function M.rewrite_article_buffer()
  run_on_buffer("journalistiek_schrijven", false)
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
  local cmd = "%!" .. shellescape(articlemeta)
  vim.cmd(cmd)
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
  local cmd = "%!" .. shellescape(articlemeta) .. " --calendar"
  vim.cmd(cmd)

  -- articlemeta --calendar updated the buffer synchronously via %!.
  -- Now read back the (possibly updated) frontmatter and append a human-
  -- readable ## Kalender section for review and editing.
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local base_lines = strip_calendar_section(lines)
  local section = build_calendar_section_lines(base_lines)

  if section then
    for _, line in ipairs(section) do
      table.insert(base_lines, line)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, base_lines)
    vim.notify("Kalenderdata toegevoegd. Controleer en pas aan, dan <leader>aw.", vim.log.levels.INFO)
  else
    vim.api.nvim_buf_set_lines(0, 0, -1, false, base_lines)
    vim.notify("Geen kalenderitem gedetecteerd in de tekst.", vim.log.levels.WARN)
  end
end

vim.keymap.set("n", "<leader>am", M.articlemeta_buffer, {
  desc = "Add article metadata",
})

vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Add calendar article and metadata",
})


function M.pubble_send()
  local file_path = vim.api.nvim_buf_get_name(0)
  local temp_file = nil
  local command

  if file_path ~= "" then
    vim.cmd("write")
    command = { pubble_send, file_path, "--create", "--write-ids", "--no-open" }
    vim.notify("Sending to Pubble...", vim.log.levels.INFO)
  else
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    if vim.trim(table.concat(lines, "\n")) == "" then
      vim.notify("Current buffer is empty", vim.log.levels.ERROR)
      return
    end
    temp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(lines, temp_file)
    command = { pubble_send, temp_file, "--create", "--write-ids", "--no-open" }
    vim.notify("Sending unsaved buffer to Pubble...", vim.log.levels.INFO)
  end

  vim.system(command, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local output = vim.trim(result.stdout or "")
        vim.notify(output ~= "" and output or "Sent to Pubble", vim.log.levels.INFO)

        local article_url = output:match("Pubble article: (https://[^\n]+)")
        if article_url then
          vim.ui.open(article_url)
        end

        if file_path ~= "" then
          -- Reload so the buffer has the IDs written back by pubble-send.
          vim.cmd("edit!")

          -- Move the file (now with IDs) to Pubble Inbox/used/.
          local used_dir = vim.fn.expand("~/Desktop/Pubble Inbox/used")
          vim.fn.mkdir(used_dir, "p")
          local filename = vim.fn.fnamemodify(file_path, ":t")
          local dest = used_dir .. "/" .. filename
          local counter = 1
          while vim.fn.filereadable(dest) == 1 do
            local stem = vim.fn.fnamemodify(filename, ":r")
            local ext  = vim.fn.fnamemodify(filename, ":e")
            dest = used_dir .. "/" .. stem .. "-" .. counter .. "." .. ext
            counter = counter + 1
          end
          vim.fn.rename(file_path, dest)
          vim.cmd("enew")
          vim.notify("Bestand verplaatst naar Pubble Inbox/used/", vim.log.levels.INFO)
        elseif temp_file ~= nil then
          local updated_lines = vim.fn.readfile(temp_file)
          vim.api.nvim_buf_set_lines(0, 0, -1, false, updated_lines)
          vim.bo.modified = true
          vim.fn.delete(temp_file)
        end
      else
        local output = vim.trim(result.stderr or result.stdout or "")
        vim.notify(output ~= "" and output or "Pubble send failed", vim.log.levels.ERROR)
        if temp_file ~= nil then
          vim.fn.delete(temp_file)
        end
      end
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
  local file_path = vim.api.nvim_buf_get_name(0)
  if file_path == "" then
    vim.notify("Buffer has no file — save it first.", vim.log.levels.ERROR)
    return
  end
  vim.cmd("write")

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local clean_lines = strip_facebook_section(lines)
  local article_text = table.concat(clean_lines, "\n")

  vim.notify("Generating Facebook post...", vim.log.levels.INFO)

  vim.system(
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

        -- Use current buffer state (not captured snapshot) so edits made while
        -- waiting are preserved. Strip any existing Facebook section first.
        local current_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local base_lines = strip_facebook_section(current_lines)
        table.insert(base_lines, "")
        table.insert(base_lines, "---")
        table.insert(base_lines, "")
        table.insert(base_lines, "## Facebook")
        table.insert(base_lines, "")
        for _, line in ipairs(vim.split(ai_output, "\n", { plain = true })) do
          table.insert(base_lines, line)
        end

        vim.api.nvim_buf_set_lines(0, 0, -1, false, base_lines)
        vim.notify("Facebook post added. Edit if needed, then <leader>aw to send.", vim.log.levels.INFO)
      end)
    end
  )
end

vim.keymap.set("n", "<leader>af", M.generate_facebook, {
  desc = "Generate Facebook post variants",
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

  vim.notify("Rewriting...", vim.log.levels.INFO)

  vim.system(
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
    end
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

  vim.notify("Thinking...", vim.log.levels.INFO)

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

  vim.system(
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
    end
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
  { label = "Bijschrift: ...  (eerste 4 regels)", insert = "Bijschrift: " },
  { label = "Foto: ...  (credit/fotograaf, eerste 4 regels)", insert = "Foto: " },
  { label = "Facebook: x  (AI genereert post)", insert = "facebook: x" },
  { label = "Facebook: eigen tekst  (geen AI)", insert = "facebook_tekst: " },
  { label = "Overig: rewrite: x  (herschrijven naar krantenstijl)", insert = "rewrite: x" },
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

return M
