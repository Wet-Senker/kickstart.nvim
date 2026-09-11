package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end

local ai = require 'ai_text'
local original_system = vim.system
local calls = {}
local callbacks = {}
vim.system = function(command, options, callback)
  if command[2] == 'tussenkopjes' or command[2] == 'streamer' or command[2] == 'kopopties' then
    table.insert(calls, command[2])
    callbacks[command[2]] = callback
    return { kill = function() end }
  end
  return original_system(command, options, callback)
end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
local body = { '=== ARTIKEL ===', '', 'Een korte kop', '' }
for i = 1, 7 do
  table.insert(body, string.rep('inhoud ', 60))
  table.insert(body, '')
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
ai.tussenkopjes_streamer({ automatic = true, buf = buf })
assert(#calls == 2 and not callbacks.kopopties, 'automatisch pad moet precies twee calls zonder kopopties doen')
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '## Kalender', '', 'Kalendergegevens' })
callbacks.tussenkopjes({ code = 0, stdout = '4: Onderwerp' })
callbacks.streamer({ code = 0, stdout = 'Een kernachtige streamer' })
assert(vim.wait(1000, function() return not vim.b[buf].article_structure_running end))
local result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(result:find('**Onderwerp**', 1, true))
assert(result:find('> Een kernachtige streamer', 1, true))
assert(result:find('Kalendergegevens', 1, true), 'parallelle sectie ging verloren')

-- Een bestaande streamer is eigen redactie. De automatische route maakt dan
-- alleen tussenkopjes en start geen kopopties- of tweede streamer-call.
calls = {}
callbacks = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '> Eigen streamer' })
ai.tussenkopjes_streamer({ automatic = true, buf = buf })
assert(#calls == 1 and calls[1] == 'tussenkopjes', 'eigen streamer startte extra AI-calls')
callbacks.tussenkopjes({ code = 0, stdout = '4: Eigen onderwerp' })
assert(vim.wait(1000, function() return not vim.b[buf].article_structure_running end))
result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(result:find('> Eigen streamer', 1, true), 'eigen streamer werd overschreven')

-- Een late opmaakreactie mag tekst die de redacteur inmiddels wijzigde niet
-- terugdraaien of aanvullen.
calls = {}
callbacks = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, body)
ai.tussenkopjes_streamer({ automatic = true, buf = buf })
vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'Eigen nieuwere alinea.' })
callbacks.tussenkopjes({ code = 0, stdout = '4: Oude tussenkop' })
callbacks.streamer({ code = 0, stdout = 'Oude streamer' })
assert(vim.wait(1000, function() return not vim.b[buf].article_structure_running end))
result = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(result:find('Eigen nieuwere alinea.', 1, true), 'late opmaak overschreef nieuwere tekst')
assert(not result:find('Oude tussenkop', 1, true), 'late tussenkop werd alsnog ingevoegd')
assert(not result:find('> Oude streamer', 1, true), 'late streamer werd alsnog ingevoegd')

calls = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'Korte kop', '', 'Korte tekst.' })
ai.tussenkopjes_streamer({ automatic = true, buf = buf })
assert(#calls == 0, 'kort artikel startte AI')
vim.system = original_system
print 'automatic structure: OK'
