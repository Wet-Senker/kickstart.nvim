-- Rubriek '5 vragen aan': de bufferhelpers plaatsen vragen en kop/intro in
-- eigen secties, zodat opnieuw vragen genereren de intro niet raakt en
-- andersom. De mailstap bouwt een correcte, ge-encodeerde mailto.
local va = require('vragen_aan')

-- Brontekst → tien (hier twee) genummerde vragen onder de sectiemarkers.
local source = { 'Bron over het onderwerp.', 'Tweede regel van de bron.' }
local with_questions = va._apply_questions(source, { 'Vraag een?', 'Vraag twee?' })
local joined = table.concat(with_questions, '\n')
assert(joined:find('=== 5 VRAGEN AAN ==='), 'sectiemarker ontbreekt')
assert(joined:find('=== VRAGEN'), 'vragenmarker ontbreekt')
assert(joined:find('1%. Vraag een%?'), 'genummerde vraag 1 ontbreekt')
assert(joined:find('2%. Vraag twee%?'), 'genummerde vraag 2 ontbreekt')
assert(joined:find('Bron over het onderwerp%.'), 'bron verdween')

-- Kop + intro plaatsen laat de vragen ongemoeid.
local with_intro = va._apply_intro(with_questions, '5 Vragen aan: Jan',
  'ZWOLLE - De aanleiding.\n\nTweede alinea van de intro.')
local ij = table.concat(with_intro, '\n')
assert(ij:find('5 Vragen aan: Jan'), 'kop ontbreekt')
assert(ij:find('ZWOLLE %- De aanleiding%.'), 'intro ontbreekt')
assert(ij:find('Tweede alinea van de intro%.'), 'tweede introalinea ontbreekt')
assert(ij:find('1%. Vraag een%?') and ij:find('2%. Vraag twee%?'), 'vragen verdwenen bij intro')

-- Opnieuw vragen genereren vervangt alleen het vragenblok; de intro blijft.
local regenerated = va._apply_questions(with_intro, { 'Nieuwe vraag?' })
local rj = table.concat(regenerated, '\n')
assert(rj:find('5 Vragen aan: Jan'), 'intro verdween bij regenereren van vragen')
assert(rj:find('ZWOLLE %- De aanleiding%.'), 'introtekst verdween bij regenereren')
assert(rj:find('1%. Nieuwe vraag%?'), 'nieuwe vraag ontbreekt')
assert(not rj:find('Vraag twee%?'), 'oude vragen zijn niet vervangen')

-- Gebruiker brengt terug tot zijn selectie → _read_questions levert schone tekst.
local trimmed = va._apply_questions(with_intro, { 'Behoud deze?', 'En deze?' })
local chosen = va._read_questions(trimmed)
assert(#chosen == 2 and chosen[1] == 'Behoud deze?' and chosen[2] == 'En deze?',
  'uitlezen van de gekozen vragen klopt niet')

-- De bron blijft bron; de intro lekt er niet in.
assert(va._source_text(with_intro):find('Bron over het onderwerp%.'), 'bron niet herkend')
assert(not va._source_text(with_intro):find('5 Vragen aan: Jan'), 'intro lekt in de bron')

-- mailto: spaties en newlines percent-ge-encodeerd; ontvanger blijft leesbaar.
local url = va._mailto('rick@example.nl', '5 vragen aan: Rick', 'Hoi Rick\nVraag 1')
assert(url:find('^mailto:rick@example.nl%?subject='), 'mailto-opbouw klopt niet: ' .. url)
assert(url:find('subject=5%%20vragen%%20aan'), 'subject niet ge-encodeerd: ' .. url)
assert(url:find('body=Hoi%%20Rick%%0AVraag%%201'), 'body niet ge-encodeerd: ' .. url)

print('vragen aan: OK')
