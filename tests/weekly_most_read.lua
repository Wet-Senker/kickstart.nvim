local weekly = require 'weekly_most_read'

local document = [[
<!-- weekly-most-read-review: 1 -->

## 1. Handmatig bekijken
Reacties: 15
Facebook: https://www.facebook.com/page_post1
Facebookstatus: handmatig: Meta-token niet ingesteld

## 2. Automatisch gelezen
Reacties: 41
Facebook: https://www.facebook.com/page_post2
Facebookstatus: automatisch: 41 reacties zonder profielgegevens

## 3. Te weinig
Reacties: 14
Facebook: https://www.facebook.com/page_post3
Facebookstatus: handmatig: Meta-token niet ingesteld
]]

local links = weekly._facebook_links_needing_review(document)
assert(#links == 1, 'alleen handmatige onderwerpen vanaf 15 reacties horen te openen')
assert(links[1] == 'https://www.facebook.com/page_post1', 'verkeerde Facebooklink geselecteerd')

print 'weekly most read: OK'
