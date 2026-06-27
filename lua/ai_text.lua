local M = {}

local aitext = vim.fn.expand("~/workspace/texttools/.venv/bin/aitext")
local articlemeta = vim.fn.expand("~/workspace/texttools/.venv/bin/articlemeta")
local pubble_web_draft = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-web-draft")
local pubble_send = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-send")
local pubble_media = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-media")

local prompts = {
  {
    label = "Journalistiek schrijven",
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

function M.menu()
  vim.ui.select(prompts, {
    prompt = "AI text action:",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end

    run_on_buffer(choice.name, choice.mode == "append")
  end)
end

function M.visual_menu()
  vim.ui.select(prompts, {
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

vim.keymap.set("n", "<leader>ai", M.menu, {
  desc = "AI text menu for whole buffer",
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
  desc = "Generate newspaper article metadata",
})

vim.keymap.set("n", "<leader>ac", M.articlemeta_calendar_buffer, {
  desc = "Generate newspaper and calendar metadata",
})


function M.pubble_send()
  local file_path = vim.api.nvim_buf_get_name(0)
  local temp_file = nil

  local command
  local options

  if file_path ~= "" then
    vim.cmd("write")

    command = { pubble_send, file_path, "--create", "--write-ids" }
    options = { text = true }

    vim.notify("Creating linked Pubble newspaper and web drafts and writing IDs back...", vim.log.levels.INFO)
  else
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local input = table.concat(lines, "\n")

    if vim.trim(input) == "" then
      vim.notify("Current buffer is empty", vim.log.levels.ERROR)
      return
    end

    temp_file = vim.fn.tempname() .. ".md"
    vim.fn.writefile(lines, temp_file)

    command = { pubble_send, temp_file, "--create", "--write-ids" }
    options = { text = true }

    vim.notify("Creating linked Pubble newspaper and web drafts from unsaved buffer...", vim.log.levels.INFO)
  end

  local article_path = file_path ~= "" and file_path or temp_file

  vim.system(command, options, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local output = vim.trim(result.stdout or "")
        vim.notify(output ~= "" and output or "Created linked Pubble drafts", vim.log.levels.INFO)

        if file_path ~= "" then
          vim.cmd("edit!")
        elseif temp_file ~= nil then
          local updated_lines = vim.fn.readfile(temp_file)
          vim.api.nvim_buf_set_lines(0, 0, -1, false, updated_lines)
          vim.bo.modified = true
          vim.notify("Updated current buffer with generated metadata and Pubble IDs", vim.log.levels.INFO)
        end

        vim.system({ pubble_media, article_path, "--upload", "--json" }, { text = true }, function(media_result)
          vim.schedule(function()
            if media_result.code == 0 then
              local decoded = vim.json.decode(media_result.stdout or "{}")
              local count = #(decoded.uploaded_images or {})
              if count > 0 then
                vim.notify(string.format("Pubble: article sent, %d image%s uploaded/linked", count, count == 1 and "" or "s"), vim.log.levels.INFO)
              end
            else
              local media_output = vim.trim(media_result.stderr or media_result.stdout or "")
              vim.notify(media_output ~= "" and media_output or "Pubble media upload failed", vim.log.levels.WARN)
            end

            if temp_file ~= nil then
              vim.fn.delete(temp_file)
            end
          end)
        end)
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
  desc = "Send article to linked Pubble drafts",
})

vim.keymap.set("n", "<leader>aw", M.pubble_send, {
  desc = "Send article to linked Pubble drafts",
})

return M
