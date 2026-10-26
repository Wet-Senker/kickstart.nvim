-- Explicit text fallback; default/browser-only has separate integration tests.
return function(photos)
  local open = photos.open
  photos.open = function(buf) return open(buf, { text = true }) end
end
