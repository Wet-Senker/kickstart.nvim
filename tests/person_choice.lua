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

-- Partij uit de byline detecteren: naam of initialen, alleen bij één treffer.
local parties = {
  'CDA', 'ChristenUnie', 'D66', 'Forum voor Democratie', 'Groep Azer-Zwitser',
  'Hart voor Kampen', 'Kampen Sociaal', 'Lid Schmidt-Blokzijl', 'Pro', 'SGP', 'VVD',
}
assert(krant._detect_party(parties, 'Column – Raadspraat, door Annelies Strikkers (FVD Kampen)\nCDA, SGP en ChristenUnie stemden tegen.') == 'Forum voor Democratie',
  'FVD uit de byline werd niet naar Forum voor Democratie gemapt')
assert(krant._detect_party(parties, 'door Jan (CDA)') == 'CDA', 'exacte partijnaam werd niet herkend')
assert(krant._detect_party(parties, 'door Piet (HvK)') == 'Hart voor Kampen', 'initialen werden niet herkend')
-- Initialen ook over koppeltekens: Groep Azer-Zwitser → GAZ, Lid Schmidt-Blokzijl → LSB.
assert(krant._detect_party(parties, 'door A (GAZ)') == 'Groep Azer-Zwitser', 'GAZ-initialen werden niet herkend')
assert(krant._detect_party(parties, 'door B (LSB)') == 'Lid Schmidt-Blokzijl', 'LSB-initialen werden niet herkend')
-- Losse vermeldingen in de tekst (geen byline) tellen niet mee.
assert(krant._detect_party(parties, 'Gewone tekst. CDA en VVD stemden tegen.') == nil,
  'body-vermelding werd ten onrechte als auteurspartij gekozen')
-- Dubbelzinnig → geen voorselectie, val terug op het menu.
assert(krant._detect_party(parties, 'door Y (Kampen)') == nil, 'dubbelzinnige token werd toch gekozen')

print 'person choice: OK'
