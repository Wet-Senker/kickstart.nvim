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

local function inspect(body)
  local result, done
  ai._inspect_article_headline(body, function(value) result, done = value, true end)
  assert(vim.wait(3000, function() return done end))
  return result
end
local function apply(body, title)
  local result, done
  ai._apply_selected_headline(body, title, function(value) result, done = value, true end)
  assert(vim.wait(3000, function() return done end))
  return result
end

local dateline = 'KAMPEN - De gemeente begint volgende week met werkzaamheden.\n\nMeer tekst.'
local inspection = inspect(lines(dateline))
assert(inspection and not inspection.has_headline, 'dateline werd ten onrechte als kop herkend')

local inserted = apply(lines(dateline), 'Werkzaamheden beginnen')
assert(
  table.concat(inserted, '\n')
    == 'Werkzaamheden beginnen\n\nKAMPEN - De gemeente begint volgende week met werkzaamheden.\n\nMeer tekst.',
  'gekozen kop verving de lead in plaats van erboven te worden ingevoegd'
)

local long_lead =
  'De gemeente begint volgende week met omvangrijke werkzaamheden in meerdere straten van de binnenstad.'
inspection = inspect(lines(long_lead))
assert(inspection and not inspection.has_headline, 'lange eerste alinea werd ten onrechte als kop herkend')

local existing = 'Oude korte kop\n\nDe lead blijft volledig staan.'
local replaced = apply(lines(existing), 'Nieuwe kop')
assert(
  table.concat(replaced, '\n') == 'Nieuwe kop\n\nDe lead blijft volledig staan.',
  'bestaande korte kop werd niet vervangen'
)

print 'headline detection: OK'
