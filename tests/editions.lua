-- De editie-adapter: cachet de lijst en biedt code→naam/label lookups. De
-- testhaak _set injecteert een vaste lijst, zodat er geen subprocess nodig is.
package.loaded['editions'] = nil
local editions = require('editions')

editions._set({
  { code = 'B', name = 'De Brug', label = 'De Brug (B)' },
  { code = 'SW', name = 'De Swollenaer', label = 'De Swollenaer (SW)' },
})

local list = editions.list()
assert(#list == 2, 'lijst niet uit de cache geserveerd')
assert(list[1].code == 'B' and list[1].label == 'De Brug (B)', 'eerste editie klopt niet')

assert(editions.name('SW') == 'De Swollenaer', 'naam-lookup faalt')
assert(editions.label('SW') == 'De Swollenaer (SW)', 'label-lookup faalt')

-- Onbekende code valt terug op de code zelf (nooit crashen op nieuwe edities).
assert(editions.name('XX') == 'XX', 'onbekende code moet terugvallen op de code')
assert(editions.by_code('XX') == nil, 'onbekende code hoort nil te geven')

-- _reset leegt de cache; daarna zou list() opnieuw ophalen (hier niet getest,
-- want dat vraagt een subprocess) — we controleren alleen dat de cache leeg is.
editions._reset()
editions._set({ { code = 'Z', name = 'Zeewolde Actueel', label = 'Zeewolde Actueel (Z)' } })
assert(#editions.list() == 1 and editions.list()[1].code == 'Z', 'reset/herset werkt niet')

print('editions: OK')
