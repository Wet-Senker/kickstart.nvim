local ai = require 'ai_text'

local function make_buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '',
    'Go-ahead wint bekerduel van DOS', '',
    'KAMPEN - Go-ahead heeft het bekerduel gewonnen.',
  })
  return buf
end

local function body_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local original_runner = ai._rubriek_check_runner
local original_confirm = ai._rubriek_confirm_simple

-- 1. Akkoord voegt de rubriekcode toe, boven de ARTIKEL-grens.
local buf = make_buffer()
ai._rubriek_check_runner = function(_, cb) cb('sport', { rubriek = 'sport', score = 9 }) end
ai._rubriek_confirm_simple = function() return 1 end
ai._offer_sport_rubriek(buf, body_of(buf))
assert(body_of(buf):find('rubriek: sport', 1, true), 'akkoord voegde de rubriekcode niet toe')
-- De code staat boven de grens (in het controleblok).
local text = body_of(buf)
assert(text:find('rubriek: sport', 1, true) < text:find('=== ARTIKEL ===', 1, true),
  'rubriekcode staat niet in het controleblok')

-- 2. Weigeren voegt niets toe en onthoudt de weigering.
local buf2 = make_buffer()
ai._rubriek_confirm_simple = function() return 2 end
ai._offer_sport_rubriek(buf2, body_of(buf2))
assert(not body_of(buf2):find('rubriek:', 1, true), 'geweigerd voorstel werd toch toegepast')
assert(vim.b[buf2].rubriek_signal_rejected == true, 'weigering werd niet onthouden')

-- 3. Een bestaande rubriekcode wordt met rust gelaten (geen dubbel).
local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf3, 0, -1, false, {
  'e: B', 'rubriek: algemeen', '', '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.',
})
ai._rubriek_confirm_simple = function() return 1 end
ai._offer_sport_rubriek(buf3, body_of(buf3))
local _, count = body_of(buf3):gsub('rubriek:', '')
assert(count == 1, 'bestaande rubriekcode werd gedupliceerd of overschreven')

-- 4. 112 houdt z'n eigen importflow: het generieke voorstel slaat 112 over.
local buf4 = make_buffer()
ai._rubriek_check_runner = function(_, cb) cb('112', { rubriek = '112', score = 12 }) end
ai._offer_sport_rubriek(buf4, body_of(buf4))
assert(not body_of(buf4):find('rubriek: 112', 1, true), '112 werd via het generieke voorstel toegepast')

ai._rubriek_check_runner = original_runner
ai._rubriek_confirm_simple = original_confirm
print 'rubriek signal: OK'
