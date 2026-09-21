-- De planningsdialoog moet leesbaar zijn.
--
-- De titel bevatte de krantprioriteit mét reden én de aanbevolen datum per
-- editie: 146 tekens, waarvan een keuzevenster er ongeveer 76 toont. Juist de
-- datums vielen weg, en de keuzeregels noemden ze ook niet. Ze horen in het
-- label zelf, want dat overleeft iedere weergave.
local ai = require 'ai_text'
local summarise = ai._summarise_publication_dates

-- Eén datum voor alle kranten: gewoon die datum.
assert(summarise { 'B 22-09', 'SW 22-09', 'ST 22-09' } == '22-09',
  'gelijke datums worden niet samengevat: ' .. tostring(summarise { 'B 22-09', 'SW 22-09' }))

-- Eén editie.
assert(summarise { 'B vandaag' } == 'vandaag', 'één editie gaat mis')

-- Verschillende datums: gegroepeerd, kranten bij hun eigen datum.
local mixed = summarise { 'B 22-09', 'SW 22-09', 'ST 22-09', 'Z 23-09', 'D 23-09' }
assert(mixed == 'B, SW, ST 22-09 · Z, D 23-09', 'verkeerd gegroepeerd: ' .. tostring(mixed))

-- Zes verschillende datums passen niet meer naast het label; dan het bereik.
local long = summarise { 'B 22-09', 'SW 23-09', 'ST 24-09', 'Z 25-09', 'D 26-09', 'K 27-09' }
assert(long:find('per editie verschillend', 1, true),
  'een lange uitsplitsing wordt niet ingekort: ' .. tostring(long))
assert(('Aanbevolen datums accepteren — ' .. long):len() <= 76,
  'de ingekorte keuzeregel is alsnog te lang')

-- Geen bruikbare invoer levert niets op; het label blijft dan ongewijzigd.
assert(summarise {} == nil, 'lege lijst geeft toch een label')
assert(summarise { 'onleesbaar' } == nil, 'een onleesbare regel geeft toch een label')

-- De samengevatte vorm past in een keuzeregel.
for _, dates in ipairs { summarise { 'B 22-09', 'SW 22-09' }, mixed, long } do
  local label = 'Aanbevolen datums accepteren — ' .. dates
  assert(#label <= 76, 'de keuzeregel wordt afgekapt: ' .. #label .. ' tekens — ' .. label)
end

print 'publication planning labels: OK'
