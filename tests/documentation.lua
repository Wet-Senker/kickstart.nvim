local test_file = debug.getinfo(1, "S").source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ":h:h")

local function read(relative_path)
  return table.concat(vim.fn.readfile(repo_root .. "/" .. relative_path), "\n")
end

local documentation = read("README.md") .. "\n" .. read("texttools-cheatsheet.md")
local ai_text = read("lua/ai_text.lua")
local init = read("init.lua")
local reminders = read("plugin/column_reminders.lua")

local documented_mappings = {
  { key = "<leader>ar", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ar"' },
  { key = "<leader>ac", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ac"' },
  { key = "<leader>ao", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ao"' },
  { key = "<leader>at", source = ai_text, registration = 'vim.keymap.set("n", "<leader>at"' },
  { key = "<leader>af", source = ai_text, registration = 'vim.keymap.set("n", "<leader>af"' },
  { key = "<leader>aw", source = ai_text, registration = 'vim.keymap.set("n", "<leader>aw"' },
  { key = "<leader>ap", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ap"' },
  { key = "<leader>ag", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ag"' },
  { key = "<leader>ah", source = ai_text, registration = 'vim.keymap.set("n", "<leader>ah"' },
  { key = "<leader>ai", source = ai_text, registration = 'vim.keymap.set("v", "<leader>ai"' },
  { key = "<leader>aq", source = ai_text, registration = 'vim.keymap.set("n", "<leader>aq"' },
  { key = "<leader>kt", source = init, registration = "vim.keymap.set('n', '<leader>kt'" },
  { key = "<leader>kp", source = reminders, registration = "vim.keymap.set('n', '<leader>kp'" },
}

for _, mapping in ipairs(documented_mappings) do
  assert(documentation:find(mapping.key, 1, true), mapping.key .. " ontbreekt in de gebruikersdocumentatie")
  assert(mapping.source:find(mapping.registration, 1, true), mapping.key .. " is gedocumenteerd maar niet geregistreerd")
end

for _, removed_mapping in ipairs({ "<leader>am", "<leader>ak" }) do
  assert(not documentation:find(removed_mapping, 1, true), removed_mapping .. " zwerft nog rond in de documentatie")
end

for _, rubric in ipairs({ "Raadspraat", "Ondernemen in Kampen", "Kamper Kiek" }) do
  assert(documentation:find(rubric, 1, true), rubric .. " ontbreekt in de rubriekdocumentatie")
end
assert(
  documentation:find("niet automatisch herkend", 1, true),
  "de grens tussen automatische detectie en handmatige rubriekkeuze ontbreekt"
)
assert(ai_text:find('label = "Rubrieken"', 1, true), "Rubrieken ontbreekt in <leader>ah")
assert(ai_text:find('vim.cmd("RubriekPlanning")', 1, true), "rubriekplanning is niet bereikbaar vanuit <leader>ah")
assert(
  reminders:find("nvim_create_user_command('RubriekPlanning'", 1, true),
  "RubriekPlanning-opdracht ontbreekt"
)

print("documentation mappings: OK")
