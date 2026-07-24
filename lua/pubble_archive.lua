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

-- Alle .md's onder het archief, nieuwste bestand eerst (op mtime). Bewust op
-- mtime en niet op bestandsnaam: het archief bevat naast YYYYMMDD-namen ook
-- fallbacknamen (verzenden-<epoch>, x_Naam) in een Historisch-submap, waar een
-- naam-sortering de volgorde zou verstoren.
local function archive_markdown_files(root)
  local files = {}
  local function scan(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end
    while true do
      local name, typ = vim.uv.fs_scandir_next(handle)
      if not name then break end
      local full = dir .. "/" .. name
      if typ == "directory" then
        scan(full)
      elseif name:match("%.md$") then
        local st = vim.uv.fs_stat(full)
        table.insert(files, { path = full, mtime = st and st.mtime.sec or 0 })
      end
    end
  end
  scan(root)
  table.sort(files, function(a, b) return a.mtime > b.mtime end)

  local paths = {}
  for _, f in ipairs(files) do table.insert(paths, f.path) end
  return paths
end
M._archive_markdown_files = archive_markdown_files

function M.find_articles()
  local root = ensure_root()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local make_entry = require("telescope.make_entry")

  pickers.new({}, {
    prompt_title = "Pubble-archief · artikelen (nieuwste eerst)",
    -- sorting_strategy = "ascending": de eerste finder-regel (nieuwste)
    -- staat bovenaan. Typen filtert daarna fuzzy zoals gebruikelijk.
    sorting_strategy = "ascending",
    finder = finders.new_table {
      results = archive_markdown_files(root),
      entry_maker = make_entry.gen_from_file { cwd = root },
    },
    sorter = conf.file_sorter {},
    previewer = conf.file_previewer {},
  }):find()
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
  vim.keymap.set("n", "<leader>pa", M.find_articles, { desc = "[P]ubble-archief: [A]rtikelen" })
  vim.keymap.set("n", "<leader>ps", M.search_contents, { desc = "[P]ubble-archief: inhoud doorzoeken" })
end

return M
