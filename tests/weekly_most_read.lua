local weekly = require 'weekly_most_read'

local document = [[
<!-- weekly-most-read-review: 2 -->

<!-- selection-start -->
1. Handmatig bekijken
2. Automatisch gelezen
3. Te weinig
<!-- selection-end -->

## Dossier 1. Handmatig bekijken
Reacties: 15
Facebook: https://www.facebook.com/page_post1
Facebookstatus: handmatig: Meta-token niet ingesteld
<!-- reactions-start: 1 -->
Plak hier desgewenst de reacties; laat leeg om ze niet te gebruiken.
<!-- reactions-end: 1 -->

## Dossier 2. Automatisch gelezen
Reacties: 41
Facebook: https://www.facebook.com/page_post2
Facebookstatus: automatisch: 41 reacties zonder profielgegevens

## Dossier 3. Te weinig
Reacties: 14
Facebook: https://www.facebook.com/page_post3
Facebookstatus: handmatig: Meta-token niet ingesteld

## Dossier 4. Niet geselecteerd
Reacties: 18
Facebook: https://www.facebook.com/page_post4
Facebookstatus: handmatig: Meta-token niet ingesteld
<!-- reactions-start: 4 -->
Plak hier desgewenst de reacties; laat leeg om ze niet te gebruiken.
<!-- reactions-end: 4 -->
]]

local links = weekly._facebook_links_needing_review(document)
assert(#links == 1, 'alleen handmatige onderwerpen vanaf 15 reacties horen te openen')
assert(links[1] == 'https://www.facebook.com/page_post1', 'verkeerde Facebooklink geselecteerd')

print 'weekly most read: OK'
