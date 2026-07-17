local M = {}

local function archive_root()
  local configured = vim.env.TEXTTOOLS_ARCHIVE_DIR
  if configured and vim.trim(configured) ~= "" then
    return vim.fn.expand(configured)
  end
  return vim.fn.expand("~/Documents/Pubble Archief")
end

local function ensure_root()
  local root = archive_root()
  vim.fn.mkdir(root, "p")
  return root
end

function M.find_articles()
  require("telescope.builtin").find_files {
    cwd = ensure_root(),
    prompt_title = "Pubble-archief · artikelen",
    find_command = { "rg", "--files", "--glob", "*.md" },
  }
end

function M.search_contents()
  require("telescope.builtin").live_grep {
    cwd = ensure_root(),
    prompt_title = "Pubble-archief · inhoud",
    glob_pattern = "*.md",
  }
end

function M.setup()
  vim.api.nvim_create_user_command("PubbleArchief", M.find_articles, {
    desc = "Zoek artikelen in het operationele Pubble-archief",
  })
  vim.api.nvim_create_user_command("PubbleArchiefZoek", M.search_contents, {
    desc = "Zoek in de inhoud van het operationele Pubble-archief",
  })
  vim.keymap.set("n", "<leader>pa", M.find_articles, { desc = "[P]ubble [A]rchief" })
  vim.keymap.set("n", "<leader>ps", M.search_contents, { desc = "[P]ubble archive [S]earch" })
end

return M
