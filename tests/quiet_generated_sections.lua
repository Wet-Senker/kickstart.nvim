local activity = require('article_activity')
local ai = require('ai_text')
activity.setup { preferences = vim.fn.tempname() .. '/activity.json' }
local native_system, native_post = vim.system, ai._post_full_article_rewrite
ai._post_full_article_rewrite = function(options) if options.after_start then options.after_start() end end
local function wait(test)
  assert(vim.wait(2000, test, 5), 'gegenereerde sectie bleef hangen: '
    .. vim.inspect(activity.snapshot(vim.api.nvim_get_current_buf())))
end
local function source()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '=== ARTIKEL ===', '', 'Kop', '', 'Artikeltekst.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local function idle(buf) return (vim.b[buf].pending_jobs or 0) == 0 and not next(activity.snapshot(buf).tasks) end
local reply, calls, last_input = nil, 0, nil
vim.system = dofile('tests/helpers/calendar_core.lua')(function(_, opts, done)
  last_input = opts.stdin
  calls, reply = calls + 1, done; return { kill = function() end }
end)
for _, title in ipairs({ 'Facebook', 'LinkedIn' }) do
  local buf = source()
  if title == 'Facebook' then ai.generate_facebook() else ai.generate_linkedin() end
  reply { code = 0, stdout = 'De socialtekst.', stderr = '' }
  wait(function() return idle(buf) end)
  assert(text(buf):find('## ' .. title .. '\n\nDe socialtekst.', 1, true))
  assert(not text(buf):find('Melding:', 1, true), 'zichtbare socialsectie kreeg een overbodige melding')
  local state = activity.snapshot(buf)
  assert(not next(state.inline) and not next(state.issues))
  assert(state.entries[#state.entries].detail, 'technische historie verloor socialresultaat')
  -- Een nieuwe fout blijft zichtbaar, ook na eerder succes.
  if title == 'Facebook' then ai.generate_facebook() else ai.generate_linkedin() end
  reply { code = 1, stdout = '', stderr = 'testfout' }
  wait(function() return text(buf):find('Melding: FOUT:', 1, true) end)
  if title == 'Facebook' then ai.generate_facebook() else ai.generate_linkedin() end
  reply { code = 0, stdout = 'De herstelde socialtekst.', stderr = '' }
  wait(function() return idle(buf) and not text(buf):find('Melding:', 1, true) end)
end
local buf = source()
local complete = { code = 0, stdout = table.concat({
  '---', 'calendar:', '  event_candidate: true', '  calendar_ready: true',
  '  calendar_title: Concert', "  event_date: '2099-10-21'", "  start_time: '20:00'",
  '  location_name: Kerk', '  city: Kampen', '  calendar_body: Muziek.', '---',
}, '\n') }
ai._check_agenda_duplicates = function(_, _, done) done(true) end
ai._apply_articlemeta_calendar_result(buf, complete, vim.api.nvim_buf_get_changedtick(buf))
wait(function() return text(buf):find('## Kalender', 1, true) end)
assert(not text(buf):find('Melding:', 1, true), 'zichtbare kalendersectie kreeg een overbodige melding')
local missing = vim.deepcopy(complete)
missing.stdout = missing.stdout:gsub('  calendar_ready: true', '  calendar_ready: false')
  :gsub('  calendar_body:', '  missing_event_fields:\n  - event_date\n  calendar_body:')
ai._apply_articlemeta_calendar_result(buf, missing, vim.api.nvim_buf_get_changedtick(buf))
wait(function() return text(buf):find('Datum ontbreekt', 1, true) end)
ai._apply_articlemeta_calendar_result(buf, complete, vim.api.nvim_buf_get_changedtick(buf))
wait(function() return not text(buf):find('Datum ontbreekt', 1, true) end)
assert(not text(buf):find('Melding:', 1, true), 'opgeloste kalenderwaarschuwing werd een succesmelding')

-- De gekozen redigeermethode is niet aan de artikeltekst af te lezen en
-- blijft daarom wel zichtbaar; een volgende methode vervangt de vorige.
buf = source()
ai.journalistic_neutralize()
reply { code = 0, stdout = vim.json.encode({ version = 1, status = 'ready',
  source_sha256 = vim.fn.sha256(last_input), article = 'Nieuwe kop\n\nBewerkte tekst.', issues = {} }), stderr = '' }
wait(function() return text(buf):find('Melding: Minimaal geredigeerd (<leader>an)', 1, true) end)
assert(activity.snapshot(buf).entries[#activity.snapshot(buf).entries].message:find('minimale redactie', 1, true))
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '***', 'Maak de kop concreter.' })
ai.ai_prompt_rewrite()
reply { code = 0, stdout = 'Nog een kop\n\nOpnieuw bewerkte tekst.', stderr = '' }
wait(function() return text(buf):find('Melding: Eigen instructie toegepast (<leader>ap)', 1, true) end)
assert(not text(buf):find('Melding: Minimaal geredigeerd', 1, true), 'oude redigeermethode bleef staan')
assert(calls == 8, 'meldingen voegden AI-calls toe')
vim.system, ai._post_full_article_rewrite = native_system, native_post
print('quiet generated sections: OK')
