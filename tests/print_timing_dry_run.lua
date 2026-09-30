-- De kranttijdkeuze mag geen AI-kosten maken vóórdat de redacteur kiest.
--
-- prepare_timing_workspace genereerde altijd meteen de kranttijdsversie zodra
-- er targets waren, en bood pas dáárna de keuze (kranttijdsversie maken /
-- alleen website / annuleren). Koos de redacteur "alleen website" of
-- "annuleren", dan was die AI-generatie voor niets gedaan. temporal_print_prepare
-- vraagt nu eerst met --dry-run (geen AI) of er een versie nodig is, en
-- genereert alleen na een expliciete "kranttijdsversie maken"-keuze.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require 'ai_text'
local dialog = require 'user_dialog'
local original_system, original_select, original_confirm =
  vim.system, dialog.select, dialog.confirm

local function new_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Tekst.',
  })
  return buf
end

local file = '/tmp/print-timing-dry-run-test.md'

local function run_prepare(responses)
  local calls = {}
  local index = 0
  vim.system = function(cmd, opts, callback)
    index = index + 1
    table.insert(calls, cmd)
    local response = responses[index]
    assert(response, 'onverwachte extra subprocesaanroep #' .. index)
    vim.schedule(function() callback(response) end)
    return { kill = function() end }
  end
  local buf = new_buf()
  local done_args
  ai._temporal_print_prepare(buf, file, {}, { 'B' }, function(...)
    done_args = { ... }
  end)
  assert(vim.wait(2000, function() return done_args ~= nil end, 5),
    'temporal_print_prepare kwam niet tot een resultaat')
  return calls, done_args
end

local function payload(fields)
  local base = {
    contract_version = 1, markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n',
    section = vim.NIL, changed = false, requires_review = false, ai_call_count = 0,
    decision_required = false, skipped_newspaper_editions = {}, targets = {},
  }
  return vim.tbl_extend('force', base, fields or {})
end
local function ok_result(fields)
  return { code = 0, stdout = vim.json.encode(payload(fields)), stderr = '' }
end

-- 1. Geen kranttijd nodig: één dry-run aanroep, geen dialoog, direct klaar.
local calls, done_args = run_prepare({ ok_result {} })
assert(#calls == 1, 'meer dan één aanroep zonder aanleiding: ' .. #calls)
assert(vim.tbl_contains(calls[1], '--dry-run'), 'de enige aanroep was geen dry-run')
assert(done_args[1] == true and done_args[3] == false,
  'zonder aanleiding hoort er niets te wijzigen')

-- 2. Wel nodig, redacteur kiest "Alleen website": geen tweede aanroep, dus
-- geen AI-kosten gemaakt. De keuze-dialoog krijgt de dry-run-aanleiding te zien.
dialog.select = function(items, opts, done)
  error('dialog.select had niet aangeroepen mogen worden voor deze keuze')
end
dialog.confirm = function(prompt, buttons, default)
  assert(prompt:find('andere tijdsversie', 1, true), 'verkeerde vraag getoond')
  -- De sneltoets (&) staat vóór "website", niet vóór "Alleen": anders zou
  -- deze optie dezelfde A-sneltoets claimen als Annuleren.
  assert(buttons:find('Kranttijdsversie maken', 1, true)
    and buttons:find('Alleen', 1, true) and buttons:find('website', 1, true)
    and buttons:find('Annuleren', 1, true),
    'niet alle drie de opties staan er: ' .. buttons)
  return 2 -- Alleen website
end
calls, done_args = run_prepare({ ok_result { requires_review = true, targets = { {} } } })
assert(#calls == 1, 'er werd een tweede (generatie-)aanroep gedaan ondanks "alleen website": ' .. #calls)
assert(not vim.tbl_contains(calls[1], '--allow-past-rewrite'))
assert(done_args[1] == true and done_args[3] == false,
  'alleen-website hoort requires_review niet als voltooide review te melden')
assert(type(done_args[4]) == 'table' and done_args[4][1] == 'B',
  'de editie moet als web-only worden teruggegeven')

-- 3. Wel nodig, redacteur kiest "Kranttijdsversie maken": een tweede aanroep
-- vindt plaats, nu zonder --dry-run (de echte generatie), en het resultaat
-- wordt toegepast.
dialog.confirm = function() return 1 end -- Kranttijdsversie maken
calls, done_args = run_prepare({
  ok_result { requires_review = true, targets = { {} } },
  ok_result {
    requires_review = true, changed = true, ai_call_count = 1,
    markdown = 'e: B\n\n=== ARTIKEL ===\n\nKop\n\nKAMPEN - Tekst.\n\n---\n\n## Kranttijdsversies\n',
    section = '## Kranttijdsversies\n',
  },
})
assert(#calls == 2, 'de bevestigde generatie vond niet plaats: ' .. #calls)
assert(vim.tbl_contains(calls[1], '--dry-run'), 'de eerste aanroep was geen dry-run')
assert(not vim.tbl_contains(calls[2], '--dry-run'),
  'de bevestigde generatie liep nog steeds als dry-run')
assert(done_args[1] == true and done_args[3] == true,
  'na echte generatie hoort requires_review/review-voltooid waar te zijn')

-- 4. Wel nodig, redacteur annuleert: geen tweede aanroep, geannuleerd resultaat.
dialog.confirm = function() return 0 end -- Annuleren
calls, done_args = run_prepare({ ok_result { requires_review = true, targets = { {} } } })
assert(#calls == 1, 'annuleren deed toch een tweede aanroep: ' .. #calls)
assert(done_args[1] == false, 'annuleren hoort geen succes te melden')

vim.system, dialog.select, dialog.confirm = original_system, original_select, original_confirm

print 'print timing dry run: OK'
