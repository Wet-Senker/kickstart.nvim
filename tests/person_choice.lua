-- Importkeuze van partij/persoon: genummerd inputlist-menu, geen confirm met
-- botsende sneltoetsletters (CDA/ChristenUnie → beide 'C' → eindeloze lus).
package.loaded.krant = nil
local krant = require 'krant'

local original_inputlist = vim.fn.inputlist
local items = { 'CDA', 'ChristenUnie', 'D66', 'Forum voor Democratie' }

-- Het menu is genummerd (1..n), niet op sneltoetsletter.
local captured
vim.fn.inputlist = function(menu) captured = menu; return 2 end
local chosen = krant._choose_detected_person(items, 'Partij:')
assert(chosen == 'ChristenUnie', 'nummerkeuze koos de verkeerde partij')
assert(captured[1] == 'Partij:', 'prompt ontbreekt in het menu')
assert(captured[2] == '1. CDA' and captured[3] == '2. ChristenUnie', 'menu is niet genummerd')

-- Annuleren (0) en buiten bereik geven nil, geen lus.
vim.fn.inputlist = function() return 0 end
assert(krant._choose_detected_person(items, 'Partij:') == nil, 'annuleren gaf toch een keuze')
vim.fn.inputlist = function() return 99 end
assert(krant._choose_detected_person(items, 'Partij:') == nil, 'ongeldige index gaf toch een keuze')

vim.fn.inputlist = original_inputlist
print 'person choice: OK'
