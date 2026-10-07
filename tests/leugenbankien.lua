-- Leugenbankien (dialectcolumn van "Appien Floep") wordt bij import automatisch
-- herkend aan de "disse stad"-uitdrukking + de ondertekening, en toegepast als
-- `x - 1 LEUGENBANKIEN` met een vaste kop, waarbij de punt na de openingszin
-- wegvalt. Beide signalen samen → automatisch; één signaal is niet genoeg.
local ar = require('article_recognition')
local krant = require('krant')

local body = table.concat({
  "'t Is maar wat in disse stad.",
  "Zakt in de geute, wat de gemeente KHC an giet doen doar snap ik niks van.",
  "En zo ziej maar weer, d'r is altied wel wat in disse stad",
  "Appien Floep",
}, "\n")

-- Herkenning: beide signalen → confidence 100, policy auto, beslissing 'auto'.
local ev = ar.evaluate(body)
local d = ev.by_id['leugenbankien']
assert(d and d.confidence == 100, 'Leugenbankien niet met volle zekerheid herkend')
assert(d.policy == 'auto', 'Leugenbankien zou automatisch moeten zijn')
local decision = ar.rubric_decision(ev)
assert(decision.action == 'auto' and decision.candidate.id == 'leugenbankien',
  'Leugenbankien wordt niet automatisch toegepast')

-- Eén signaal (alleen de uitdrukking, geen ondertekening) is onvoldoende.
local half = ar.evaluate("Er is van alles in disse stad te doen deze week.")
local hd = half.by_id['leugenbankien']
assert(not hd or hd.confidence < ar.RUBRIC_PROMPT_THRESHOLD,
  'één los signaal mag Leugenbankien niet activeren')

-- Toepassing: kop + werktitel + punt weg + prio.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '' })
krant.apply_detected_rubric('leugenbankien', buf, { normalized_body = body }, function() end)
local txt = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(txt:find('working_title: "x %- 1 LEUGENBANKIEN"'), 'verkeerde/ontbrekende werktitel')
assert(txt:find('\nLeugenbankien\n', 1, true), 'vaste kop "Leugenbankien" ontbreekt')
assert(txt:find('in disse stad%.') == nil, 'punt na de openingszin is niet verwijderd')
assert(txt:find("in disse stad\n", 1, true), 'openingszin zonder punt ontbreekt')
assert(txt:find('Appien Floep', 1, true), 'ondertekening is verdwenen')
assert(txt:find('\nprio: 1', 1, true), 'print+web-column Leugenbankien hoort prio 1 te krijgen')

-- Al toegepast (kop staat er al) → niet opnieuw aanbieden.
local applied = ar.evaluate(txt)
local ad = applied.by_id['leugenbankien']
assert(ad and ad.state == 'already_applied', 'toegepaste Leugenbankien wordt niet als zodanig herkend')

print('leugenbankien: OK')
