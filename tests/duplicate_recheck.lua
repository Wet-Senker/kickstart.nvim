-- Handmatig opnieuw draaien van de doublurecontrole (<leader>ad).
local ai = require 'ai_text'

-- De actie moet als toets bestaan; een functie zonder mapping is onbereikbaar
-- voor de redacteur (ARCHITECTUURPRINCIPES principe 12). Zelfde controlewijze
-- als tests/documentation.lua: lees de registratie uit de bron.
local test_file = debug.getinfo(1, 'S').source:sub(2)
local repo_root = vim.fn.fnamemodify(test_file, ':h:h')
local ai_text_source = table.concat(vim.fn.readfile(repo_root .. '/lua/ai_text.lua'), '\n')

assert(
  ai_text_source:find('require("user_dialog").keymap("n", "<leader>ad"', 1, true),
  'geen registratie van <leader>ad in ai_text.lua'
)
assert(type(ai.recheck_duplicates) == 'function', 'recheck_duplicates ontbreekt')

-- Loopt de controle al, dan start er geen tweede en volgt alleen een melding.
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.' })
vim.b[buf].pubble_duplicate_check_running = true

local started = false
local original = ai._check_duplicate_stage
ai._check_duplicate_stage = function() started = true end
ai.recheck_duplicates(buf)
ai._check_duplicate_stage = original

assert(started == false, 'er is een tweede doublurecontrole gestart')
assert(
  vim.b[buf].pubble_duplicate_checked_body == nil,
  'de gecontroleerd-markering is gewijzigd terwijl de controle al liep'
)

-- De hercontrole gebruikt de alleen-lezen resolver, niet de verzendgoedkeuring.
local resolver = ai._calendar_edition_resolver
local workflow = require('texttools_notify').workflow
local notices, pending, checks = {}, nil, 0
require('texttools_notify').workflow = function(message) notices[#notices + 1] = message end
vim.b[buf].pubble_duplicate_check_running = false
ai._calendar_edition_resolver = function(target, text, done, review_only)
  assert(target == buf and review_only == true, 'hercontrole vroeg verzendgoedkeuring')
  assert(text:find('e: B', 1, true))
  pending = done
end
ai._check_duplicate_stage = function(target, codes, stage, done, file, agenda)
  checks = checks + 1
  assert(target == buf and stage == 'hercontroleren' and agenda == true and file == nil)
  assert(vim.deep_equal(codes, { 'B', 'K', 'SW' }))
  done(true)
end
vim.b[buf].pubble_duplicate_checked_body = 'oude controle'
ai.recheck_duplicates(buf)
pending({ editions = { 'B', 'K', 'SW' } })
assert(checks == 1 and vim.b[buf].pubble_duplicate_checked_body == nil)

-- Resolverfout is niet hetzelfde als een succesvolle lege editiekeuze.
ai.recheck_duplicates(buf)
pending(nil, 'Ongeldige editie: bestaatniet')
assert(checks == 1 and notices[#notices]:find('Ongeldige editie: bestaatniet', 1, true))
assert(not notices[#notices]:find('Geen editie bekend', 1, true))
assert(notices[#notices]:find('<leader>ad', 1, true), 'fout mist vervolgstap')
ai.recheck_duplicates(buf)
pending({ editions = {} })
assert(checks == 1 and notices[#notices]:find('Geen editie bekend', 1, true))

-- De leescontrole gaat door als de e:-regel tijdens resolutie wordt bewerkt;
-- zoeken verandert geen publicatiebestemmingen en is krantoverstijgend.
vim.b[buf].pubble_duplicate_checked_body = 'niet wissen'
ai.recheck_duplicates(buf)
vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: SW' })
pending({ editions = { 'B', 'K', 'SW' } })
assert(checks == 2 and vim.b[buf].pubble_duplicate_checked_body == nil)

ai._calendar_edition_resolver, ai._check_duplicate_stage = resolver, original
require('texttools_notify').workflow = workflow

-- De echte adapter kiest hetzelfde procesaantal, maar de review-CLI.
local system, command, response = vim.system
vim.system = function(cmd, _, done) command, response = cmd, done; return {} end
local resolved
ai._calendar_edition_resolver(buf, 'e: SW\n\n=== ARTIKEL ===\n\nKop', function(value) resolved = value end, true)
assert(command[1]:find('pubble%-duplicates$'), 'review ging toch via pubble-send')
assert(vim.tbl_contains(command, '--resolve-editions') and vim.tbl_contains(command, '--require-article-boundary'))
response({ code = 0, stdout = '{"editions":["SW"]}', stderr = '' })
assert(vim.wait(1000, function() return resolved ~= nil end))
assert(vim.deep_equal(resolved.editions, { 'SW' }) and (vim.b[buf].pending_jobs or 0) == 0)
vim.system = system
print 'duplicate recheck: OK'
