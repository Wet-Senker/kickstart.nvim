local instance = require('article_instance')
local activity = require('article_activity')
local jobs = require('buffer_jobs')
local source = vim.api.nvim_get_current_buf()
activity.setup({ preference_path = vim.fn.tempname() })
assert(not instance.setup(), 'gewone editor kreeg artikelafsluitbewaking')
vim.env.TEXTTOOLS_ARTICLE_INSTANCE = '1'
vim.env.TEXTTOOLS_ARTICLE_TITLE = 'Artikel · Kop 100%\nveilig'
assert(instance.setup())
assert(vim.o.title and vim.o.titlestring == 'Artikel · Kop 100%% veilig', 'titel is niet veilig ingesteld')
assert(not instance.pending())

-- Ook nog niet getoonde en uitgestelde vragen horen bij het proces.
local dialog = require('user_dialog')
dialog.select({ 'Ja' }, { native = true, required = true, source_buf = source }, function() end)
assert(instance.pending(), 'vraag in queue werd niet herkend')
assert(vim.wait(500, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
vim.fn.maparg('<Esc>', 'n', false, true).callback()
assert(instance.pending(), 'uitgestelde vraag werd niet herkend')
dialog.resume()
assert(vim.wait(500, function() return vim.api.nvim_win_get_config(0).relative == 'editor' end))
vim.fn.maparg('<CR>', 'n', false, true).callback()
assert(not instance.pending(), 'beantwoorde vraag bleef blokkeren')

-- Bewaking gebruikt bestaande taakregistraties, ook voor verborgen bronnen.
local token = jobs.start(source, 'Artikel herschrijven')
vim.cmd('vnew')
assert(not instance.close('qa'), 'afsluiten brak een lopende taak af')
vim.api.nvim_feedkeys(':qa' .. vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
assert(vim.api.nvim_buf_is_valid(source), 'bron verdween bij geweigerde afsluiting')
jobs.finish(token)
assert(not instance.pending())

vim.b[source].publication_in_progress = true
assert(not instance.close('qa!'), 'qa! omzeilde lopende publicatie')
vim.b[source].publication_in_progress = false
activity.start(source, 'read', 'Archief zoeken')
assert(instance.pending(), 'alleen-lezen achtergrondtaak werd gemist')
activity.finish(source, 'read')
assert(not instance.pending())

-- Een hulpvenster sluiten is geen procesafsluiting en blijft mogelijk.
token = jobs.start(source, 'Testtaak')
vim.cmd('q')
assert(jobs.count(source) == 1, 'hulpvenster sluiten annuleerde de taak')
jobs.finish(token)

-- De expliciete nooduitgang is herkenbaar en bewaart de standaardbewaking.
assert(vim.api.nvim_get_commands({}).TexttoolsSluiten.bang)
local command, native_cmd = nil, vim.cmd
vim.cmd = function(value) command = value end
token = jobs.start(source, 'Testtaak')
assert(instance.close('qa!', true) and command == 'qa!', 'bewuste nooduitgang ontbreekt')
vim.cmd = native_cmd
jobs.finish(token)
vim.api.nvim_del_augroup_by_name('TexttoolsArticleInstance')
print('article instance: OK')
