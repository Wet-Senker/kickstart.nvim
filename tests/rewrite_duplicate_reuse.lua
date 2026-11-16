local ai = require 'ai_text'
local scans, resolved, resolve, editing_only = 0, { 'B' }, nil, false
local original_system = vim.system
local original_runner = ai._duplicate_stage_runner
ai._duplicate_stage_runner = function(_, done)
  scans = scans + 1
  done(true, { performed = true, candidates = {}, editing_only = editing_only })
end
vim.system = function(command, _, done)
  if vim.tbl_contains(command, '--resolve-editions') then
    resolve = function()
      done { code = 0, stdout = vim.json.encode {
        editions = resolved, names = {}, has_explicit_editions = true,
      } }
    end
  else
    assert(command[1]:match('articlemeta$'), 'onverwacht subprocess: ' .. command[1])
    done { code = 0, stdout = '' }
  end
  return {}
end

local function put(buf, scope, body)
  local document = scope .. '\nagenda: nee\n\n=== ARTIKEL ===\n\n' .. body
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(document, '\n', { plain = true }))
  return document
end

local function run(case)
  editing_only = case.editing_only == true
  resolved = case.codes or { 'B' }
  local buf = vim.api.nvim_create_buf(false, true)
  local original = put(buf, 'e: B', 'Oude kop\n\nDe aangeleverde tekst.')
  ai._check_duplicate_stage(buf, { 'B' }, 'importeren', function(ok) assert(ok) end)
  assert(vim.wait(1000, function() return (vim.b[buf].pending_jobs or 0) == 0 end))
  editing_only = false
  local duplicate_review = ai._duplicate_review_snapshot(buf,
    vim.split(case.source or original, '\n', { plain = true }))
  local rewritten = put(buf, case.scope or 'e: B', 'Nieuwe kop\n\nDe bewerkte tekst.')
  local before = scans
  resolve = nil
  ai._post_full_article_rewrite {
    buf = buf, document = rewritten, original_content = case.source or original,
    duplicate_review = duplicate_review,
  }
  assert(vim.wait(1000, function() return resolve ~= nil end))
  if case.late_edit then
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Handmatige wijziging.' })
  end
  resolve()
  assert(vim.wait(1000, function()
    return (vim.b[buf].pending_jobs or 0) == 0 and not vim.b[buf].pubble_duplicate_gate_pending
  end))
  assert(scans - before == case.expected, case.label .. ': onjuist aantal controles')
  if case.expected == 0 then
    assert(ai._duplicate_check_is_current(buf), 'AW mist de overgenomen controle')
    ai._check_duplicate_stage(buf, { 'B' }, 'verzenden', function(ok) assert(ok) end)
    assert(scans == before, 'AW start alsnog een webcontrole')
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Daarna handmatig aangepast.' })
    assert(not ai._duplicate_check_is_current(buf), 'handmatige wijziging erfde het akkoord')
  end
end

run { label = 'dezelfde bron en scope', expected = 0 }
run { label = 'andere bron', source = 'Andere bron.', expected = 1 }
run { label = 'nieuwe suggestie', scope = 'e: B, SUGGESTIE, SW', expected = 1 }
run { label = 'andere opgeloste edities', codes = { 'SW' }, expected = 1 }
run { label = 'nieuwe body tijdens resolver', late_edit = true, expected = 1 }
run { label = 'alleen toestemming om te bewerken', editing_only = true, expected = 1 }
vim.system, ai._duplicate_stage_runner = original_system, original_runner
