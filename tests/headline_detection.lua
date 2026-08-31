package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end
package.preload['fidget.notification'] = function()
  return { notify = function() end }
end

local ai = require 'ai_text'

local function lines(text)
  return vim.split(text, '\n', { plain = true })
end

local dateline = 'KAMPEN - De gemeente begint volgende week met werkzaamheden.\n\nMeer tekst.'
local inspection = ai._inspect_article_headline(lines(dateline))
assert(inspection and not inspection.has_headline, 'dateline werd ten onrechte als kop herkend')

local inserted = ai._apply_selected_headline(lines(dateline), 'Werkzaamheden beginnen')
assert(
  table.concat(inserted, '\n')
    == 'Werkzaamheden beginnen\n\nKAMPEN - De gemeente begint volgende week met werkzaamheden.\n\nMeer tekst.',
  'gekozen kop verving de lead in plaats van erboven te worden ingevoegd'
)

local long_lead =
  'De gemeente begint volgende week met omvangrijke werkzaamheden in meerdere straten van de binnenstad.'
inspection = ai._inspect_article_headline(lines(long_lead))
assert(inspection and not inspection.has_headline, 'lange eerste alinea werd ten onrechte als kop herkend')

local existing = 'Oude korte kop\n\nDe lead blijft volledig staan.'
local replaced = ai._apply_selected_headline(lines(existing), 'Nieuwe kop')
assert(
  table.concat(replaced, '\n') == 'Nieuwe kop\n\nDe lead blijft volledig staan.',
  'bestaande korte kop werd niet vervangen'
)

print 'headline detection: OK'
