local ai = require 'ai_text'

local function buffer_text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

local function overijssel_lines(prefix)
  local lines = prefix or {}
  table.insert(lines, '=== ARTIKEL ===')
  table.insert(lines, '')
  table.insert(lines, 'Overijsselse campagne tegen zorgcriminaliteit')
  table.insert(lines, '')
  table.insert(lines, 'Inwoners van Overijssel leren signalen herkennen.')
  table.insert(lines, 'De provincie Overijssel ondersteunt de campagne.')
  return lines
end

local imported = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(imported, 0, -1, false, overijssel_lines())
ai._edition_autodetect(imported, buffer_text(imported))
assert(
  vim.wait(5000, function() return buffer_text(imported):find('e: B, SW, ST, K', 1, true) ~= nil end, 20),
  'provinciebrede bestemming werd bij import niet ingevuld'
)
assert(vim.b[imported].edition_recognition_done == true, 'eenmalige importmarkering ontbreekt')

local explicit = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(explicit, 0, -1, false, overijssel_lines { 'e: SW', '' })
ai._edition_autodetect(explicit, buffer_text(explicit))
assert(
  buffer_text(explicit):find('e: SW', 1, true) ~= nil and buffer_text(explicit):find('e: B, SW, ST, K', 1, true) == nil,
  'bestaande e:-regel werd bij import overschreven'
)

local original_confirm = ai._edition_rewrite_confirm
local kept = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(kept, 0, -1, false, overijssel_lines { 'e: SW', '' })
local asked
ai._edition_rewrite_confirm = function(current_label, detected_label, source)
  asked = { current_label, detected_label, source }
  return 1
end
local keep_done = false
ai._reconcile_editions_after_rewrite(kept, buffer_text(kept), function(ok) keep_done = ok end)
assert(vim.wait(5000, function() return keep_done end, 20), 'rewritecontrole rondde niet af')
assert(asked and asked[1] == 'De Swollenaer', 'afwijkende rewritebestemming werd niet voorgelegd')
assert(buffer_text(kept):find('e: SW', 1, true), 'huidige editie werd niet behouden')

local changed = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(changed, 0, -1, false, overijssel_lines { 'e: SW', '' })
ai._edition_rewrite_confirm = function() return 2 end
local change_done = false
ai._reconcile_editions_after_rewrite(changed, buffer_text(changed), function(ok) change_done = ok end)
assert(vim.wait(5000, function() return change_done end, 20), 'rewritewijziging rondde niet af')
assert(buffer_text(changed):find('e: B, SW, ST, K', 1, true), 'bevestigde nieuwe bestemming werd niet vastgelegd')
ai._edition_rewrite_confirm = original_confirm

assert(ai._needs_edition_send_confirmation { has_explicit_editions = false }, 'afgeleide aw-bestemming vraagt geen bevestiging')
assert(not ai._needs_edition_send_confirmation { has_explicit_editions = true }, 'expliciete aw-bestemming vraagt onnodig bevestiging')

print 'edition detection: OK'
