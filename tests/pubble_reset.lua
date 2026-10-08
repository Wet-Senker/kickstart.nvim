-- Reset van een mislukte Pubble-verzending: het plan tonen, bevestigen en pas
-- daarna de lokale tekst terugzetten. De beslissingen zelf zitten in Python.
package.preload['fidget.notification'] = function() return { notify = function() end } end

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. '/inbox', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = tmp .. '/inbox'

local reset = require 'pubble_reset'
local original_system, original_confirm = vim.system, reset._confirm

local snapshot = tmp .. '/herstelkopie.md'
vim.fn.writefile({ 'e: B', '', '=== ARTIKEL ===', '', 'Originele tekst.' }, snapshot)

local function plan(overrides)
  return vim.tbl_extend('force', {
    items = {
      { kind = 'web', edition = 'B', object_id = 375506, action = 'offline', label = 'Webartikel De Brug', note = '' },
      { kind = 'web', edition = 'SW', object_id = 375507, action = 'offline', label = 'Webartikel De Swollenaer', note = '' },
      { kind = 'krant_bron', edition = 'B', object_id = 375500, action = 'handmatig',
        label = "Koppelconcept 'z -'", note = '', url = 'https://pubble.example/375500' },
      { kind = 'teams', edition = 'B', object_id = vim.NIL, action = 'info',
        label = 'Teams-melding De Brug', note = 'niet in te trekken' },
    },
    snapshot_status = 'available',
    snapshot_path = snapshot,
  }, overrides or {})
end

local function new_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '---', 'web:', '  x: 1', '---', 'half verzonden staat' })
  return buf
end

-- vim.system-mock: eerst het plan, daarna (indien gevraagd) de apply.
local function mock(plan_data, apply_result)
  local calls = {}
  vim.system = function(cmd, opts, callback)
    local sub = cmd[#cmd]
    table.insert(calls, sub)
    local payload = sub == 'plan' and plan_data or apply_result
    vim.schedule(function()
      callback({ code = payload.code or 0, stdout = vim.json.encode(payload.body or payload), stderr = '' })
    end)
    return { kill = function() end }
  end
  return calls
end

local function lines(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end
local function settle() vim.wait(300, function() return false end, 10) end

-- 1. De samenvatting groepeert per actie en noemt de herstelkopie.
local summary = table.concat(reset._summary(plan()), '\n')
assert(summary:find('Gaat offline', 1, true) and summary:find('Webartikel De Brug (375506)', 1, true), 'offline-sectie ontbreekt')
assert(summary:find('zelf opruimen', 1, true) and summary:find("Koppelconcept 'z -' (375500)", 1, true), 'handmatige sectie ontbreekt')
assert(summary:find('niet worden teruggedraaid', 1, true) and summary:find('Teams-melding', 1, true), 'niet-terug-te-draaien sectie ontbreekt')
assert(summary:find('terug naar vlak vóór <leader>aw', 1, true), 'herstelkopie niet genoemd')
local no_copy = table.concat(reset._summary(plan({ snapshot_status = 'missing', snapshot_path = vim.NIL })), '\n')
assert(no_copy:find('Geen herstelkopie', 1, true), 'ontbrekende herstelkopie niet genoemd')

-- 2. Bevestigd en alles offline: tekst terug, bufferstate leeg, tijdelijk bestand weg.
local temp = tmp .. '/inbox/mislukt.md'
vim.fn.writefile({ 'staat met ID' }, temp)
local buf = new_buf()
vim.b[buf].failed_send_file = temp
vim.b[buf].publication_in_progress = false
vim.b[buf].publication_review_state = { display_dates = {} }
vim.b[buf].late_newspaper_decision = { mode = 'force' }
reset._confirm = function() return 1 end
local calls = mock(plan(), { offline = {}, errors = {}, restore_from = snapshot, plan = plan() })
reset.reset(buf)
assert(vim.wait(2000, function() return table.concat(lines(buf), '\n'):find('Originele tekst', 1, true) end, 10), 'tekst niet teruggezet')
assert(vim.deep_equal(calls, { 'plan', 'apply' }), 'verkeerde aanroepvolgorde: ' .. table.concat(calls, ','))
assert(vim.b[buf].failed_send_file == nil, 'failed_send_file bleef staan')
assert(vim.b[buf].publication_review_state == nil and vim.b[buf].late_newspaper_decision == nil, 'bufferstate bleef staan')
assert(vim.fn.filereadable(temp) == 0, 'het mislukte tijdelijke bestand bleef staan')

-- 3. Annuleren: alleen het plan is opgevraagd, niets verandert.
buf = new_buf()
reset._confirm = function() return 2 end
calls = mock(plan(), { offline = {}, errors = {}, restore_from = snapshot })
reset.reset(buf)
settle()
assert(vim.deep_equal(calls, { 'plan' }), 'annuleren riep toch apply aan: ' .. table.concat(calls, ','))
assert(lines(buf)[5] == 'half verzonden staat', 'tekst veranderde bij annuleren')

-- 4. Niet alles offline: de tekst (met de ID\'s) blijft staan.
buf = new_buf()
reset._confirm = function() return 1 end
calls = mock(plan(), { offline = {}, errors = { 'RuntimeError: Pubble weigert' }, restore_from = snapshot })
reset.reset(buf)
settle()
assert(vim.deep_equal(calls, { 'plan', 'apply' }))
assert(lines(buf)[5] == 'half verzonden staat', 'tekst werd teruggezet terwijl niet alles offline ging')

-- 5. Zonder herstelkopie: wel offline, tekst blijft.
buf = new_buf()
local nocopy = plan({ snapshot_status = 'missing', snapshot_path = vim.NIL })
calls = mock(nocopy, { offline = {}, errors = {}, restore_from = vim.NIL, plan = nocopy })
reset.reset(buf)
settle()
assert(vim.deep_equal(calls, { 'plan', 'apply' }))
assert(lines(buf)[5] == 'half verzonden staat', 'tekst veranderde zonder herstelkopie')

-- 6. De tekst verandert tijdens de reset: nooit overschrijven.
buf = new_buf()
reset._confirm = function() return 1 end
vim.system = function(cmd, _, callback)
  local sub = cmd[#cmd]
  vim.schedule(function()
    if sub == 'apply' then vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'nieuwere bewerking' }) end
    local body = sub == 'plan' and plan() or { offline = {}, errors = {}, restore_from = snapshot, plan = plan() }
    callback({ code = 0, stdout = vim.json.encode(body), stderr = '' })
  end)
  return { kill = function() end }
end
reset.reset(buf)
settle()
assert(lines(buf)[6] == 'nieuwere bewerking' and lines(buf)[5] == 'half verzonden staat', 'nieuwere bewerking werd overschreven')

-- 7. Tijdens een lopende verzending gebeurt er niets.
buf = new_buf()
vim.b[buf].publication_in_progress = true
calls = mock(plan(), {})
reset.reset(buf)
settle()
assert(#calls == 0, 'reset startte tijdens een lopende verzending')

-- 8. Niets om terug te zetten: geen vraag.
buf = new_buf()
local asked = false
reset._confirm = function() asked = true; return 1 end
calls = mock({ items = {}, snapshot_status = 'missing', snapshot_path = vim.NIL }, {})
reset.reset(buf)
settle()
assert(not asked, 'er werd gevraagd terwijl er niets terug te zetten was')
assert(vim.deep_equal(calls, { 'plan' }))

vim.system, reset._confirm = original_system, original_confirm
vim.fn.delete(tmp, 'rf')
print 'pubble reset: OK'
