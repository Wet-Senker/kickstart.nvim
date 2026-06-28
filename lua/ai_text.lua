local M = {}

local aitext = vim.fn.expand("~/workspace/texttools/.venv/bin/aitext")
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

function M.articlemeta_calendar_buffer()
  local cmd = "%!" .. shellescape(articlemeta) .. " --calendar"
  vim.cmd(cmd)
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
          vim.cmd("edit!")
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
    if lines[i] == "## Facebook bericht" then
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
        table.insert(base_lines, "## Facebook bericht")
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

return M
