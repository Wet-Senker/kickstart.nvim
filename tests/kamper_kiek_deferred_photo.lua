local ai = require 'ai_text'
local krant = require 'krant'
local layout = require 'layout_export'
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. '/inbox', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = tmp .. '/inbox'
krant.config.desktop = tmp .. '/Desktop'
local day = tonumber(os.date('%u'))
local week = os.date('%V', day == 1 and os.time() or (os.time() + 7 * 24 * 3600))
local expected_directory = krant.config.desktop .. '/' .. week .. ' Gemeentenieuws'
vim.fn.mkdir(expected_directory, 'p')
local messages, topic_calls = {}, 0
vim.notify = function(message) messages[#messages + 1] = message end
ai._kamper_kiek_topics_runner = function(_, _, done)
  topic_calls = topic_calls + 1
  done { code = 0, stdout = 'cultuur, familie, wijken en muziek' }
end
local function fresh()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e:', '', '=== ARTIKEL ===', '',
    'De Kamper kiek op de wîêk:', '', '1). Cultuur in Kampen.', '', '2). Familie op bezoek.', '',
    '3). Wijken ontmoeten elkaar.', '', '4). Kerstconcert AMDG op 12 december.' })
  return buf
end
local template
for _, item in ipairs(krant.templates) do if item.id == 'kamper_kiek' then template = item end end
local buf, completed = fresh(), nil
assert(krant.kamperkiek_flow(template, buf, nil, function(ok) completed = ok end))
assert(vim.wait(5000, function() return completed ~= nil end, 10))
assert(completed and topic_calls == 1)
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(text:find('e: B', 1, true) and text:find('z - KAMPER KIEK', 1, true))
assert(text:find('In De Brug kijkt burgemeester', 1, true))
assert(text:find('## Facebook', 1, true) and text:find('## LinkedIn', 1, true))
assert(not table.concat(messages, '\n'):find('Geen foto gevonden', 1, true))
local plan = assert(layout.pending(buf))
assert(plan.dir == expected_directory and plan.txt_name == '2.kamperkiekFOTO.txt')
assert(plan.img_name == '2.kamperkiek.jpg')
assert(vim.fn.filereadable(plan.dir .. '/' .. plan.img_name) == 0, 'te vroege fotokopie')
assert(vim.fn.filereadable(plan.dir .. '/' .. plan.txt_name) == 0, 'te vroege tekstexport')
-- A photo added afterwards is used by the existing post-publication media export.
vim.fn.writefile({ 'later toegevoegde foto' }, tmp .. '/inbox/late.png')
local original_system = vim.system
local command, callback
vim.system = function(cmd, _, done) command, callback = cmd, done; return {} end
local finished
layout.finalize_with_media(buf, tmp .. '/published.md', function(path, err) finished = { path, err } end)
assert(command[3] == 'texttools.layout_media' and vim.tbl_contains(command, '--image-name'))
assert(vim.tbl_contains(command, '2.kamperkiek.jpg'))
callback { code = 0, stdout = '{}' }
assert(vim.wait(1000, function() return finished ~= nil end, 5))
assert(finished[1] == plan.dir .. '/' .. plan.txt_name and not finished[2])
vim.system = original_system
-- Multiple files do not block preparing the text either; publication resolves media.
vim.fn.writefile({ 'andere foto' }, tmp .. '/inbox/another.jpg')
local second = fresh()
assert(krant.kamperkiek_flow(template, second))
assert(vim.wait(5000, function() return topic_calls == 2 end, 10))
assert(layout.pending(second))
vim.fn.delete(tmp, 'rf')
-- Adding media does not invalidate topic extraction; body edits do.
local late
ai._kamper_kiek_topics_runner = function(_, _, done) late = done end
ai._generate_kamper_kiek_social(second, '3. Wijken ontmoeten elkaar.')
vim.api.nvim_buf_set_lines(second, 0, 0, false, { 'c: Nieuwe fotograaf' })
late { code = 0, stdout = 'nieuwe onderwerpen' }
local with_media = table.concat(vim.api.nvim_buf_get_lines(second, 0, -1, false), '\n')
assert(with_media:find('deze week nieuwe onderwerpen', 1, true))
ai._generate_kamper_kiek_social(second, '3. Wijken ontmoeten elkaar.')
vim.api.nvim_buf_set_lines(second, -1, -1, false, { '## Nieuwe sectie', 'Nieuwe tekst.' })
-- An actual article-body edit blocks stale results.
local lines = vim.api.nvim_buf_get_lines(second, 0, -1, false)
for i, line in ipairs(lines) do if line:find('Cultuur in Kampen', 1, true) then lines[i] = '1. Gewijzigde cultuurtekst.' end end
vim.api.nvim_buf_set_lines(second, 0, -1, false, lines)
late { code = 0, stdout = 'achterhaalde onderwerpen' }
assert(not table.concat(vim.api.nvim_buf_get_lines(second, 0, -1, false), '\n'):find('deze week achterhaalde onderwerpen', 1, true))
print('Kamper Kiek deferred photo: OK')
