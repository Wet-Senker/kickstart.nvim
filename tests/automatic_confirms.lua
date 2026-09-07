local ai = require 'ai_text'
local original_duplicate_runner = ai._duplicate_stage_runner
ai._duplicate_stage_runner = function(_, callback)
  callback(true, { performed = false, candidates = {} })
end

local original_select = vim.ui.select
vim.ui.select = function() error 'automatische bevestiging opende onverwacht fzf-lua' end

-- De automatische 112-vraag gebruikt de ingebouwde confirm-route.
local original_112_confirm = ai._112_confirm
local asked_112
ai._112_confirm = function(prompt)
  asked_112 = prompt
  return 2
end
local emergency = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(emergency, 0, -1, false, {
  'Politie en brandweer kwamen na een aanrijding ter plaatse.',
  'Een ambulance bracht een slachtoffer naar het ziekenhuis.',
})
ai._offer_112_template(emergency, 12, 'bij import')
assert(asked_112 and asked_112:find('112%-bericht behandelen'), '112-confirm werd niet gebruikt')
assert(vim.b[emergency]._112_rejected == true, '112-afwijzing werd niet onthouden')
assert(vim.b[emergency]._112_prompt_pending == false, '112-promptstatus bleef hangen')
ai._112_confirm = original_112_confirm

-- Conflicterende rubrieken gebruiken eveneens confirm en kunnen veilig worden
-- afgewezen zonder template of fzf-menu.
local original_rubric_confirm = ai._rubric_confirm
local candidates_seen
ai._rubric_confirm = function(decision)
  candidates_seen = #decision.candidates
  return nil
end
local conflict = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(conflict, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'De Kamper kiek op de wîêk: 1). Eerste punt. 2). Tweede punt. 3). Derde punt.',
  'Politie, brandweer en ambulance kwamen na een aanrijding ter plaatse.',
})
ai._article_autodetect(conflict)
assert(
  vim.wait(5000, function() return candidates_seen ~= nil end, 20),
  'conflicterende rubriekherkenning werd niet afgerond'
)
assert(candidates_seen == 2, 'conflicterende rubrieken kwamen niet in confirm')
assert(vim.b[conflict]._112_rejected == true, 'conflictafwijzing onthield 112 niet')
assert(vim.b[conflict].rubric_recognition_prompt_pending == false, 'rubriekprompt bleef hangen')
ai._rubric_confirm = original_rubric_confirm

-- De automatische vraag na terugkeer uit Mail gebruikt dezelfde veilige
-- dialoogklasse. Een Nee-keuze mag geen extern remindercommando starten.
local reminders = dofile(vim.fn.getcwd() .. '/plugin/column_reminders.lua')
local asked_mail
reminders._sent_confirm = function(label)
  asked_mail = label
  return 2
end
reminders._confirm_sent_on_return({ label = 'Testpersoon', id = 'test', series = 'raadspraat' })
vim.api.nvim_exec_autocmds('FocusGained', {})
vim.wait(500, function() return asked_mail ~= nil end)
assert(asked_mail == 'Testpersoon', 'Mail-terugkeervraag gebruikte confirm niet')

vim.ui.select = original_select
ai._duplicate_stage_runner = original_duplicate_runner
print 'automatic confirms: OK'
