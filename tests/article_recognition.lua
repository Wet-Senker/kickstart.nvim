local recognition = require('article_recognition')

local supplied_kiek = [[
De Kamper kiek op de wîêk: 1). Ik zit op het pluche. 2). Het Oranjefeest
is speciaal. 3). Jong en oud geniet van het Oogstfeest. 4). Een bloemetje.
]]

local evaluation = recognition.evaluate(supplied_kiek)
local kiek = evaluation.by_id.kamper_kiek
assert(kiek.confidence == 100, 'ondubbelzinnige Kamper Kiek kreeg geen score 100')
assert(#kiek.evidence >= 4, 'Kamper-Kiekscore legt zijn signalen niet uit')
local decision = recognition.rubric_decision(evaluation)
assert(decision.action == 'auto', 'ondubbelzinnige Kamper Kiek wordt niet automatisch toegepast')
assert(decision.candidate.id == 'kamper_kiek', 'verkeerde automatische rubriek')

decision = recognition.rubric_decision(recognition.evaluate('Dit is een Kamper Kiek zonder herkenbare nummering.'))
assert(decision.action == 'confirm', 'onzekere Kamper Kiek hoort om bevestiging te vragen')

decision = recognition.rubric_decision(recognition.evaluate('1. Gewoon punt. 2. Nog een punt. 3. Tot slot.'))
assert(decision.action == 'none', 'willekeurige genummerde lijst werd als Kamper Kiek gezien')

local supplied_hondenhoek = [[
Wat hebben honden en mensen gemeen voor wat betreft hun relatie tot hun voorouders?

De hond communiceert met zijn hele lichaam en werkt nauw samen met de mens.

Bert Nieuwenhuis.
]]
local hondenhoek = recognition.evaluate(supplied_hondenhoek).by_id.hondenhoek
assert(hondenhoek.confidence == 100, 'Bert Nieuwenhuis plus hond kreeg geen Hondenhoekscore 100')
assert(#hondenhoek.evidence == 2, 'Hondenhoek legt auteur- en hondensignaal niet uit')
local hondenhoek_decision = recognition.rubric_decision(recognition.evaluate(supplied_hondenhoek))
assert(hondenhoek_decision.action == 'auto', 'zekere Hondenhoek wordt niet automatisch toegepast')
assert(hondenhoek_decision.candidate.id == 'hondenhoek', 'verkeerde automatische Hondenhoekrubriek')

hondenhoek_decision = recognition.rubric_decision(recognition.evaluate('Hondenhoek:'))
assert(hondenhoek_decision.action == 'confirm', 'alleen een Hondenhoekkop hoort om bevestiging te vragen')
hondenhoek_decision = recognition.rubric_decision(recognition.evaluate('Een gewone hond speelde vandaag in het park.'))
assert(hondenhoek_decision.action == 'none', 'een gewoon hondenbericht werd als Hondenhoek gezien')

local already_formatted = [[
De Kamper Kiek op de wîêk

In De Brug kijkt burgemeester Sander de Rouwe wekelijks in fotovorm terug op de afgelopen week.

1. Eerste punt.
2. Tweede punt.
3. Derde punt.
]]
local existing = recognition.evaluate(already_formatted)
assert(existing.by_id.kamper_kiek.state == 'already_applied', 'bestaand template werd niet herkend')
assert(recognition.rubric_decision(existing).action == 'none', 'bestaand template zou opnieuw worden toegepast')

local existing_with_incident = recognition.evaluate(
  already_formatted .. '\nPolitie, brandweer en ambulance kwamen na een aanrijding ter plaatse.'
)

local existing_hondenhoek = recognition.evaluate([[
Hondenhoek

In de column Hondenhoek belicht kynologisch gedragstherapeut en doorgewinterd hondenkenner Bert Nieuwenhuis telkens één actueel gedragsthema.

De hond leert door samenwerking.
]])
assert(existing_hondenhoek.by_id.hondenhoek.state == 'already_applied', 'bestaande Hondenhoek werd niet herkend')
assert(recognition.rubric_decision(existing_hondenhoek).action == 'none', 'bestaande Hondenhoek zou opnieuw worden toegepast')
assert(
  recognition.rubric_decision(existing_with_incident).action == 'none',
  'incidentwoorden in een bestaande Kamper Kiek openden onterecht het 112-menu'
)

local emergency = recognition.evaluate(
  'Politie en brandweer kwamen na een aanrijding ter plaatse. Een ambulance bracht een slachtoffer naar het ziekenhuis.'
)
assert(emergency.by_id['112'].points >= recognition.EMERGENCY_THRESHOLD, 'bestaande 112-score ging verloren')
assert(recognition.rubric_decision(emergency).action == 'confirm', '112 mag nooit zonder bevestiging worden toegepast')

local investigated_door_fire = recognition.evaluate([[
Politie onderzoekt brand bij voordeur woning Bereklauw

KAMPEN - De politie onderzoekt een brand bij de voordeur van een woning in Kampen. Kort voor half één vannacht kwam daarover een melding binnen. Er zou een knal zijn gehoord. De brand heeft schade aan de woning veroorzaakt.

De politie onderzoekt wat er precies is gebeurd en wie bij het incident betrokken is. Forensische Opsporing heeft ter plaatse sporen veiliggesteld. Ook worden onder meer camerabeelden bekeken.

De politie roept mensen die afgelopen nacht iets hebben gezien of camerabeelden van het incident hebben op zich te melden. Dat kan via 0900-8844.
]])
assert(
  investigated_door_fire.by_id['112'].points == recognition.EMERGENCY_THRESHOLD,
  'politieonderzoek naar een brand moet via de combinatiebonus de 112-drempel halen'
)
assert(
  recognition.rubric_decision(investigated_door_fire).action == 'confirm',
  'politieonderzoek naar de voordeurbrand moet om 112-bevestiging vragen'
)

local conflict = recognition.evaluate(
  supplied_kiek .. '\nPolitie, brandweer en ambulance kwamen na een aanrijding ter plaatse.'
)
local conflict_decision = recognition.rubric_decision(conflict)
assert(conflict_decision.action == 'confirm', 'botsende rubrieksignalen moeten een menu openen')
assert(#conflict_decision.candidates == 2, 'conflictmenu bevat niet beide rubriekkandidaten')

-- De herkenning blijft ruim onder het afgesproken budget en doet geen I/O.
local benchmark_text = supplied_kiek .. string.rep('\nExtra gewone artikeltekst zonder nieuwe signalen.', 100)
local iterations = 200
local started = vim.uv.hrtime()
for _ = 1, iterations do recognition.evaluate(benchmark_text) end
local average_ms = ((vim.uv.hrtime() - started) / 1e6) / iterations
assert(average_ms < 5, string.format('artikelherkenning is te traag: %.3f ms gemiddeld', average_ms))

-- Integratie: één centrale importcall past Kamper Kiek zonder keuzemenu toe.
local tmp = vim.fn.tempname()
local inbox = tmp .. '/inbox'
local desktop = tmp .. '/Desktop'
local stock = tmp .. '/stock'
vim.fn.mkdir(inbox, 'p')
vim.fn.mkdir(desktop, 'p')
vim.fn.mkdir(stock, 'p')
vim.env.TEXTTOOLS_INBOX_DIR = inbox

local original_select = vim.ui.select
vim.ui.select = function() error('zekere Kamper Kiek opende onverwacht een bevestigingsmenu') end

local ai_text = require('ai_text')
local krant = require('krant')
krant.config.desktop = desktop
krant.config.stock_images = stock
assert(
  ai_text._112_signal_score('Politie en brandweer kwamen na een aanrijding ter plaatse.')
    >= recognition.EMERGENCY_THRESHOLD,
  'bestaande 112-workflows zijn niet met de centrale scorer verbonden'
)

local missing_photo_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(missing_photo_buf)
vim.api.nvim_buf_set_lines(missing_photo_buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'De Kamper kiek op de wîêk: 1). Eerste punt. 2). Tweede punt. 3). Derde punt.',
})
local before_missing_photo = table.concat(vim.api.nvim_buf_get_lines(missing_photo_buf, 0, -1, false), '\n')
ai_text._article_autodetect(missing_photo_buf)
assert(
  table.concat(vim.api.nvim_buf_get_lines(missing_photo_buf, 0, -1, false), '\n') == before_missing_photo,
  'Kamper-Kiekherkenning zonder foto wijzigde het artikel gedeeltelijk'
)
assert(
  vim.b[missing_photo_buf].rubric_recognition_pending == 'kamper_kiek:photo_missing',
  'ontbrekende Kiek-foto is niet als herstelbare bufferstatus opgeslagen'
)

vim.fn.writefile({ 'foto' }, inbox .. '/kiek.jpg')
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'De Kamper kiek op de wîêk: 1). Eerste punt. 2). Tweede punt. 3). Derde punt.',
})
ai_text._article_autodetect(buf)

local output = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
assert(
  output:find('newspaper:\n  working_title: "z - 1 Kamper Kiek"', 1, true),
  'automatische Kamper Kiek kreeg niet de vaste z-werktitel'
)
assert(output:find('De Kamper Kiek op de wîêk', 1, true), 'automatisch template ontbreekt')
assert(output:find('\n1. Eerste punt.\n2. Tweede punt.\n3. Derde punt.', 1, true), 'automatische nummering klopt niet')
assert(vim.b[buf].recognized_rubric == 'kamper_kiek', 'herkende rubriek is niet in de bufferstatus opgeslagen')
assert(vim.b[buf].recognized_rubric_score == 100, 'herkenningsscore is niet in de bufferstatus opgeslagen')
assert(require('layout_export').pending(buf), 'automatische Kamper Kiek verloor de vormgevingsexport')

local once = output
ai_text._article_autodetect(buf)
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') == once, 'herkenning draaide tweemaal')

-- Integratie: Hondenhoek gebruikt dezelfde centrale route, een vaste
-- stockfoto en de expliciet meegegeven buffer (ook als die niet actief is).
vim.fn.delete(inbox, 'rf')
vim.fn.mkdir(inbox, 'p')
vim.fn.writefile({ 'stockfoto' }, stock .. '/hondenhoek.jpg')
local honden_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(honden_buf, 0, -1, false, {
  '=== ARTIKEL ===',
  '',
  'Hondenhoek:',
  '',
  'Wat hebben honden en mensen gemeen?',
  '',
  'De hond werkt nauw samen met de mens.',
  '',
  'Bert Nieuwenhuis.',
})
local sentinel_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(sentinel_buf, 0, -1, false, { 'niet wijzigen' })
vim.api.nvim_set_current_buf(sentinel_buf)
ai_text._article_autodetect(honden_buf)

local honden_output = table.concat(vim.api.nvim_buf_get_lines(honden_buf, 0, -1, false), '\n')
assert(honden_output:find('newspaper:\n  working_title: "z - 1 Hondenhoek"', 1, true), 'Hondenhoekfrontmatter ontbreekt')
assert(honden_output:find('\nHondenhoek\n', 1, true), 'vaste Hondenhoektitel ontbreekt')
assert(not honden_output:find('\nHondenhoek:\n', 1, true), 'aangeleverde Hondenhoekkop bleef dubbel staan')
assert(honden_output:find('Wat hebben honden en mensen gemeen?', 1, true), 'Hondenhoektekst is gewijzigd')
assert(honden_output:find('Bert Nieuwenhuis.', 1, true), 'aangeleverde Hondenhoekauteur is verwijderd')
assert(vim.b[honden_buf].recognized_rubric == 'hondenhoek', 'Hondenhoekstatus ontbreekt')
assert(vim.b[honden_buf].recognized_rubric_score == 100, 'Hondenhoekscore ontbreekt')
assert(require('layout_export').pending(honden_buf), 'Hondenhoek verloor de vormgevingsexport')
assert(vim.fn.filereadable(inbox .. '/hondenhoek.jpg') == 1, 'Hondenhoekstockfoto ontbreekt in de Inbox')
assert(table.concat(vim.api.nvim_buf_get_lines(sentinel_buf, 0, -1, false), '\n') == 'niet wijzigen', 'verkeerde buffer is gewijzigd')

local honden_once = honden_output
ai_text._article_autodetect(honden_buf)
assert(table.concat(vim.api.nvim_buf_get_lines(honden_buf, 0, -1, false), '\n') == honden_once, 'Hondenhoekherkenning draaide tweemaal')

vim.ui.select = original_select

vim.fn.delete(tmp, 'rf')
print(string.format('article recognition: OK (%.3f ms gemiddeld)', average_ms))
