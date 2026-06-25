local M = {}

local aitext = vim.fn.expand("~/workspace/texttools/.venv/bin/aitext")
local articlemeta = vim.fn.expand("~/workspace/texttools/.venv/bin/articlemeta")
local pubble_web_draft = vim.fn.expand("~/workspace/texttools/.venv/bin/pubble-web-draft")

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


function M.pubble_send_to_web()
  local file = vim.fn.expand("%:p")

  if file == "" then
    vim.notify("Current buffer has no file path", vim.log.levels.ERROR)
    return
  end

  if vim.bo.modified then
    vim.cmd("write")
  end

  vim.notify("Creating inactive Pubble web draft...", vim.log.levels.INFO)

  vim.system({ pubble_web_draft, file, "--create" }, { text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        local output = vim.trim(result.stdout or "")
        vim.notify(output ~= "" and output or "Created inactive Pubble web draft", vim.log.levels.INFO)
      else
        local output = vim.trim(result.stderr or result.stdout or "")
        vim.notify(output ~= "" and output or "Pubble web draft failed", vim.log.levels.ERROR)
      end
    end)
  end)
end

vim.api.nvim_create_user_command("PubbleSendToWeb", M.pubble_send_to_web, {
  desc = "Create inactive Pubble web draft for current Markdown file",
})

vim.keymap.set("n", "<leader>aw", M.pubble_send_to_web, {
  desc = "Send article to Pubble web draft",
})

return M
