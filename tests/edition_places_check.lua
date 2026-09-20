-- Plaatsencontrole: signaleren bij import, en bij <leader>ar alleen opnieuw
-- vragen als de tekst naar andere kranten is gaan wijzen.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'

local function resolved(places, editions)
  return { places = places, editions = editions or { 'K' }, names = { 'Nieuwsbode de Kop' } }
end

local LUTTELGEEST = { place = 'Luttelgeest', editions = { 'K' }, names = { 'Nieuwsbode de Kop' } }
local IJSSELMUIDEN = { place = 'IJsselmuiden', editions = { 'B' }, names = { 'De Brug' } }
local DRONTEN = { place = 'Dronten', editions = { 'D' }, names = { 'De Drontenaar' } }

-- De sleutel gaat over kranten, niet over plaatsnamen. Dezelfde plaats komt als
-- dateline in kapitalen én in de lopende tekst voor; dat mag geen verschil zijn.
local shouted = { place = 'LUTTELGEEST', editions = { 'K' }, names = { 'Nieuwsbode de Kop' } }
assert(
  ai._edition_places_signature(resolved { LUTTELGEEST })
    == ai._edition_places_signature(resolved { shouted }),
  'de schrijfwijze van een plaats verandert de sleutel'
)

-- Volgorde mag ook niet uitmaken.
assert(
  ai._edition_places_signature(resolved { IJSSELMUIDEN, DRONTEN })
    == ai._edition_places_signature(resolved { DRONTEN, IJSSELMUIDEN }),
  'de volgorde van plaatsen verandert de sleutel'
)

-- Een extra vindplaats van een al bekende krant is geen verandering.
local extra_place_same_paper = { place = 'Ens', editions = { 'K' }, names = { 'Nieuwsbode de Kop' } }
assert(
  ai._edition_places_signature(resolved { LUTTELGEEST })
    == ai._edition_places_signature(resolved { LUTTELGEEST, extra_place_same_paper }),
  'een tweede plaats van dezelfde krant telt als verandering'
)

-- Een plaats van een andere krant is dat wél.
assert(
  ai._edition_places_signature(resolved { LUTTELGEEST })
    ~= ai._edition_places_signature(resolved { LUTTELGEEST, IJSSELMUIDEN }),
  'een nieuwe krant wordt niet als verandering gezien'
)

-- Welke kranten zijn gevonden maar niet gekozen, en waaraan te danken?
local three = resolved({ LUTTELGEEST, IJSSELMUIDEN, DRONTEN }, { 'K' })
local order, by_code = ai._unchosen_edition_places(three, { 'K' })
assert(vim.deep_equal(order, { 'B', 'D' }), 'verkeerde kranten voorgesteld: ' .. vim.inspect(order))
assert(by_code.B.name == 'De Brug', 'naam ontbreekt')
assert(by_code.B.places[1] == 'IJsselmuiden', 'plaats ontbreekt bij de krant')
assert(by_code.D.places[1] == 'Dronten', 'plaats ontbreekt bij de krant')

-- De gekozen krant zelf komt nooit als voorstel terug.
local none = ai._unchosen_edition_places(resolved { LUTTELGEEST }, { 'K' })
assert(#none == 0, 'de eigen krant wordt als voorstel aangeboden')

-- De beslisregel.
local first_time = ai._edition_places_need_question(nil, three, { 'K' })
assert(first_time == true, 'zonder eerdere controle wordt niets gevraagd')

local known = ai._edition_places_signature(three)
assert(
  ai._edition_places_need_question(known, three, { 'K' }) == false,
  'er wordt opnieuw gevraagd terwijl er niets veranderde'
)

-- Tekst gewijzigd: er komt een krant bij.
local four = resolved(
  { LUTTELGEEST, IJSSELMUIDEN, DRONTEN, { place = 'Zwolle', editions = { 'SW' }, names = { 'De Swollenaer' } } },
  { 'K' }
)
assert(
  ai._edition_places_need_question(known, four, { 'K' }) == true,
  'een nieuw gevonden krant leidt niet tot een vraag'
)

-- Alles al gekozen: niets te vragen, ook al is de sleutel anders.
assert(
  ai._edition_places_need_question('X', three, { 'K', 'B', 'D' }) == false,
  'er wordt gevraagd terwijl alle gevonden kranten al gekozen zijn'
)

-- Oudere Python zonder places-veld mag de herschrijving nooit blokkeren.
assert(
  ai._edition_places_need_question(nil, { editions = { 'K' } }, { 'K' }) == false,
  'een antwoord zonder plaatsenscan leidt tot een vraag'
)

print 'edition places check: OK'

-- Een provincie is context, geen reden voor een eigen krant. Zonder deze regel
-- stelt elk landelijk bericht meteen alle kranten voor.
local with_province = {
  editions = { 'K' },
  names = { 'Nieuwsbode de Kop' },
  places = {
    LUTTELGEEST,
    { place = 'Overijssel', kind = 'province', editions = { 'B', 'SW', 'ST' },
      names = { 'De Brug', 'De Swollenaer', 'De Stadskoerier' } },
  },
}
local province_only = ai._unchosen_edition_places(with_province, { 'K' })
assert(#province_only == 0, 'een provincie levert kranten op als voorstel')
assert(
  ai._edition_places_need_question(nil, with_province, { 'K' }) == false,
  'een provincie alleen leidt tot een vraag'
)

-- Een echte plaats ernaast telt wel.
table.insert(with_province.places, IJSSELMUIDEN)
local mixed = ai._unchosen_edition_places(with_province, { 'K' })
assert(vim.deep_equal(mixed, { 'B' }), 'naast de provincie wordt de plaats niet gezien')

-- Een antwoord zonder kind-veld (oudere Python) wordt als plaats gelezen.
local legacy = { editions = { 'K' }, places = { { place = 'Dronten', editions = { 'D' }, names = { 'De Drontenaar' } } } }
assert(#(ai._unchosen_edition_places(legacy, { 'K' })) == 1, 'zonder kind-veld valt de plaats weg')

print 'edition places provinces: OK'

-- De gedeelde provincie moet de AI-aanroep halen, anders moet die haar zelf uit
-- de brontekst afleiden.
local captured = {}
local original_system = vim.system
vim.system = function(command, _, callback)
  table.insert(captured, table.concat(command, ' '))
  return {}
end
ai._edition_variant_runner(0, 'SW', 'bron', function() end, {
  code = 'SW', editions = { 'SW', 'ST', 'K' },
  prompt = 'krantversie_algemeen', areas = { 'Overijssel' },
})
ai._edition_variant_runner(0, 'B', 'bron', function() end, {
  code = 'B', editions = { 'B' }, prompt = 'krantversie', areas = {},
})
vim.system = original_system

assert(captured[1]:find('--shared%-area Overijssel'),
  'de gedeelde provincie gaat niet mee: ' .. tostring(captured[1]))
assert(not captured[2]:find('--shared-area', 1, true),
  'een eigen krantversie krijgt ten onrechte een gedeelde provincie')

print 'edition places shared area: OK'

-- Een zelf getypte e:-regel is een genomen beslissing. Daar hoort geen vraag
-- bij, ook niet als de tekst plaatsen van andere kranten noemt. Dit raakt onder
-- meer het weekendbericht: dat heeft een vaste editieregel maar noemt soms een
-- plaats uit een ander verspreidingsgebied.
local explicit = {
  editions = { 'B' },
  names = { 'De Brug' },
  has_explicit_editions = true,
  places = {
    { place = 'Kampen', kind = 'place', editions = { 'B' }, names = { 'De Brug' } },
    { place = 'Zwolle', kind = 'place', editions = { 'SW' }, names = { 'De Swollenaer' } },
  },
}
assert(ai._edition_places_need_question(nil, explicit, { 'B' }) == false,
  'een expliciete editieregel wordt alsnog in twijfel getrokken')

-- Zonder die regel gaat het programma wél vragen; dat was de oorspronkelijke fout.
local derived = vim.deepcopy(explicit)
derived.has_explicit_editions = false
assert(ai._edition_places_need_question(nil, derived, { 'B' }) == true,
  'een afgeleide bestemming levert geen vraag meer op')

print 'edition places explicit: OK'
