-- De weekendbatch mag de reviewblokkade niet overslaan.
--
-- <leader>aw routeerde eerst op weekend_batch_id en pas daarna op openstaande
-- krantversies. Een weekendbuffer met een niet-goedgekeurde versie zou zo
-- ongecontroleerd de batchroute in gaan. Dat kan vandaag niet gebeuren — een
-- weekendbuffer hoort bij één krant — maar die aanname mag niet stilzwijgend
-- de enige bescherming zijn.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local edition_review = require 'edition_review'
local agenda_menu = require 'agenda_menu'

local original_reason = edition_review.send_block_reason
local original_prepare = agenda_menu.prepare_weekend_batch_send
local original_notify = vim.notify

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.' })
vim.b[buf].weekend_batch_id = '123-1'
vim.api.nvim_set_current_buf(buf)

local prepared, warned = false, nil
agenda_menu.prepare_weekend_batch_send = function() prepared = true; return true end
vim.notify = function(message) warned = message end

-- 1. Openstaande krantversie: de batch mag niet starten.
edition_review.send_block_reason = function()
  return 'Een krantversie heeft nog niet opgeslagen of goedgekeurde wijzigingen.'
end
ai.pubble_send(buf)
assert(prepared == false, 'de weekendbatch startte ondanks een openstaande krantversie')
assert(warned and warned:find('krantversie', 1, true),
  'er volgde geen bruikbare melding: ' .. tostring(warned))

-- 2. Niets in de weg: de batch gaat gewoon door.
prepared, warned = false, nil
edition_review.send_block_reason = function() return nil end
ai.pubble_send(buf)
assert(prepared == true, 'de weekendbatch startte niet terwijl er niets in de weg stond')

edition_review.send_block_reason = original_reason
agenda_menu.prepare_weekend_batch_send = original_prepare
vim.notify = original_notify

print 'weekend batch review block: OK'
