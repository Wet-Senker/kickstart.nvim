local ai_text = require('ai_text')

local allowed, message = ai_text._active_publication_photo_guard({ has_photo = false })
assert(not allowed, 'actief publiceren zonder foto werd niet geblokkeerd')
assert(
  message and message:find('geen foto gekoppeld', 1, true),
  'fotobeveiliging gaf geen begrijpelijke reden'
)

assert(
  ai_text._active_publication_photo_guard({ has_photo = true }),
  'actief publiceren met foto werd geblokkeerd'
)
assert(
  ai_text._active_publication_photo_guard({}),
  'een oudere resolver zonder fotoveld werd lokaal onterecht geblokkeerd'
)

print('publication photo guard: OK')
