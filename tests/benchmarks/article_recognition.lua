-- Zelfde invoer/budget als de eerdere functietest, maar met opwarming en
-- herhaalde steekproeven. Draai zonder gelijktijdige zware tests/builds.
local recognition = require('article_recognition')
local supplied_kiek = [[
De Kamper kiek op de wîêk: 1). Ik zit op het pluche. 2). Het Oranjefeest
is speciaal. 3). Jong en oud geniet van het Oogstfeest. 4). Een bloemetje.
]]
local text = supplied_kiek .. string.rep('\nExtra gewone artikeltekst zonder nieuwe signalen.', 100)
for _ = 1, 30 do recognition.evaluate(text) end
local samples, iterations = {}, 200
for _ = 1, 5 do
  collectgarbage('collect')
  local start = vim.uv.hrtime()
  for _ = 1, iterations do recognition.evaluate(text) end
  samples[#samples + 1] = ((vim.uv.hrtime() - start) / 1e6) / iterations
end
table.sort(samples)
local median = samples[3]
print(string.format('artikelherkenning: mediaan %.3f ms; bereik %.3f–%.3f ms; 5 × 200 scans',
  median, samples[1], samples[5]))
assert(median < 5, string.format('artikelherkenning overschrijdt 5 ms: mediaan %.3f ms', median))
