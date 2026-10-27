package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai = require('ai_text')
local review = require('newspaper_review')
local dialog = require('user_dialog')
local original_select, original_system = dialog.select, vim.system
local function plan()
  local items = {}
  for i, code in ipairs({ 'B', 'K', 'SW' }) do
    items[i] = { edition = code, publication_name = ({ 'De Brug', 'Nieuwsbode de Kop', 'De Swollenaer' })[i],
      newspaper_date = i == 3 and '2026-10-28' or '2026-11-03', reason = 'Datumcontext verschilt.',
      choices = { { id = 'website', label = 'Alleen website' },
        { id = 'rewrite', label = 'Aparte kranttekst maken; webtekst behouden' },
        { id = 'use_web', label = 'Webtekst ongewijzigd' } } }
  end
  return { contract_version = 1, items = items }
end
local function buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'e: B, K, SW', '', '=== ARTIKEL ===', '', 'Kop', '', 'Tekst.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local buf, asks, result = buffer(), {}, nil
dialog.select = function(items, opts, done) asks[#asks + 1] = { items = items, opts = opts, done = done } end
review.collect(plan(), { buf = buf }, function(choices) result = choices end)
assert(#asks == 1 and asks[1].opts.prompt:find('De Brug — krant van 03-11-2026 — 1 van 3', 1, true))
asks[1].done(nil, 1) -- website
assert(not result and #asks == 2)
assert(asks[2].opts.prompt:find('Nieuwsbode de Kop', 1, true))
asks[2].done(nil, 4) -- terug
assert(#asks == 3 and asks[3].opts.default == 1)
asks[3].done(nil, 2) -- Brug nu herschrijven
asks[4].done(nil, 3) -- Kop ongewijzigd
assert(not result and asks[5].opts.prompt:find('28-10-2026 — 3 van 3', 1, true))
asks[5].done(nil, 1) -- Swollenaer website
assert(vim.deep_equal(result, { B = 'rewrite', K = 'use_web', SW = 'website' }))

local function deadline()
  return { signature = 'per-paper', late_editions = { 'B', 'K', 'SW' }, items = {}, choice_plan = plan() }
end
-- Annuleren, Escape en edits: geen halve uitzonderingen/besluiten.
for _, mode in ipairs({ 'cancel', 'escape', 'edit' }) do
  buf, asks = buffer(), {}
  local before, finished = text(buf), nil
  ai._review_late_newspapers(buf, deadline(), function(ok) finished = ok end)
  asks[1].done(nil, 1)
  assert(text(buf) == before and not vim.b[buf].late_newspaper_decision)
  if mode == 'edit' then vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere tekst.' }) end
  asks[2].done(nil, mode == 'escape' and nil or (mode == 'edit' and 2 or 5))
  assert(finished == false and not vim.b[buf].late_newspaper_decision and not vim.b[buf].skip_newspaper_editions)
  assert(not text(buf):find('krantuitzondering:', 1, true))
end
buf, asks = buffer(), {}
local finished
ai._review_late_newspapers(buf, deadline(), function(ok) finished = ok end)
asks[1].done(nil, 2)
asks[2].done(nil, 3)
assert(finished == nil and not vim.b[buf].late_newspaper_decision)
asks[3].done(nil, 1)
assert(finished == true)
assert(vim.deep_equal(vim.b[buf].skip_newspaper_editions, { 'SW' }))
assert(vim.deep_equal(vim.b[buf].late_newspaper_decision.editions, { 'B', 'K' }))
assert(vim.deep_equal(vim.b[buf].late_newspaper_decision.use_web_editions, { 'K' }))
assert(require('buffer_revision').matches(buf, vim.b[buf].late_newspaper_decision.use_web_revision))
assert(text(buf):find('krantuitzondering: SW', 1, true))
local ask_count = #asks
ai._review_late_newspapers(buf, deadline(), function(ok) finished = ok end)
assert(finished == true and #asks == ask_count, 'gemengde afgeronde ronde werd opnieuw gevraagd')
-- Een gecontroleerde aparte krantsectie maakt de oorspronkelijke keuzes niet
-- ongeldig. De volgende verzending hoeft dezelfde vragen niet opnieuw te tonen.
do
  local calls, done_args = 0, nil
  local file = vim.fn.tempname() .. '.md'
  vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), file)
  local original = text(buf)
  vim.system = function(_, _, callback)
    calls = calls + 1
    local section = '## Kranttijdsversies\n'
    local payload = { markdown = original, changed = false, decision_required = true, targets = {
      { edition = 'B' }, { edition = 'K' } }, choice_plan = plan() }
    if calls == 2 then
      payload.markdown, payload.section = original .. '\n\n' .. section, section
      payload.changed, payload.decision_required, payload.requires_review = true, false, true
    end
    vim.schedule(function() callback({ code = 0, stdout = vim.json.encode(payload), stderr = '' }) end)
    return { kill = function() end }
  end
  ai._temporal_print_prepare(buf, file, {}, { 'B', 'K', 'SW' }, function(...) done_args = { ... } end)
  assert(vim.wait(1000, function() return done_args ~= nil end))
  assert(calls == 2 and #asks == ask_count and done_args[1] and done_args[3])
  assert(require('buffer_revision').matches(buf, vim.b[buf].late_newspaper_decision.use_web_revision))
  ai._review_late_newspapers(buf, deadline(), function(ok) finished = ok end)
  assert(finished == true and #asks == ask_count)
  vim.fn.delete(file)
end

-- Beide timingaanleidingen gebruiken één ronde en pas daarna één generatie.
local function argument(cmd, name)
  for i, value in ipairs(cmd) do if value == name then return vim.json.decode(cmd[i + 1]) end end
end
for _, past in ipairs({ false, true }) do
  for _, cancel in ipairs({ false, true }) do
    buf, asks = buffer(), {}
    local file = vim.fn.tempname() .. '.md'
    vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), file)
    local before, calls, done_args = text(buf), {}, nil
    vim.system = function(cmd, _, callback)
      calls[#calls + 1] = cmd
      local payload = { markdown = before, changed = false, requires_review = false, targets = {} }
      if #calls == 1 then
        payload.requires_review, payload.decision_required = not past, past
        payload.choice_plan = plan()
        for _, item in ipairs(payload.choice_plan.items) do
          payload.targets[#payload.targets + 1] = { edition = item.edition }
        end
      else
        assert(#asks == 3, 'generatie startte vóór laatste keuze')
        assert(vim.deep_equal(argument(cmd, '--editions'), { 'B', 'K' }))
        assert(vim.deep_equal(argument(cmd, '--use-web-editions'), { 'K' }))
        assert(not vim.tbl_contains(cmd, '--dry-run') and vim.tbl_contains(cmd, '--allow-past-rewrite'))
      end
      vim.schedule(function() callback({ code = 0, stdout = vim.json.encode(payload), stderr = '' }) end)
      return { kill = function() end }
    end
    ai._temporal_print_prepare(buf, file, {}, { 'B', 'K', 'SW' }, function(...) done_args = { ... } end)
    assert(vim.wait(1000, function() return #asks == 1 end))
    asks[1].done(nil, 2)
    asks[2].done(nil, 3)
    assert(#calls == 1 and text(buf) == before)
    asks[3].done(nil, cancel and 5 or 1)
    assert(vim.wait(1000, function() return done_args ~= nil end))
    assert(done_args[1] == not cancel)
    if cancel then
      assert(#calls == 1 and text(buf) == before)
      assert(table.concat(vim.fn.readfile(file), '\n') == before and not vim.b[buf].skip_newspaper_editions)
    else
      assert(#calls == 2 and vim.deep_equal(done_args[4], { 'SW' }))
      assert(table.concat(vim.fn.readfile(file), '\n'):find('krantuitzondering: SW', 1, true))
    end
    vim.fn.delete(file)
  end
end
dialog.select, vim.system = original_select, original_system
-- Echte native overlay: sneltoetsen, terug en Escape werken zonder confirm/wait.
buf = buffer()
local native_result, native_done
review.collect(plan(), { buf = buf }, function(choices) native_result, native_done = choices, true end)
local function press(key)
  assert(vim.wait(1000, function()
    return type(vim.fn.maparg(key, 'n', false, true).callback) == 'function'
  end))
  vim.fn.maparg(key, 'n', false, true).callback()
end
press('h')
press('t')
press('b')
press('h')
press('w')
assert(native_done and vim.deep_equal(native_result, { B = 'use_web', K = 'rewrite', SW = 'website' }))
native_done = false
review.collect(plan(), { buf = buf }, function(choices) native_result, native_done = choices, true end)
press('w')
press('<Esc>')
assert(native_done and native_result == nil)
print('newspaper review: OK')
