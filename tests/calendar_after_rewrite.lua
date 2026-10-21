-- Na een eerdere niet-herkenning mag ar alsnog agenda herkennen, maar eerst
-- beoordelen. Een bestaande of bewust verwijderde agenda blijft onaangeroerd.
local ai = require 'ai_text'
local original_system = vim.system
local starts, reviews, answer, metadata_calls = 0, 0, nil, 0
local body = 'Concert\n\nKAMPEN - Op 18 november begint om 19.30 uur een concert in de kerk. '
  .. 'De toegang is gratis. Aanmelden kan via de website.'
vim.system = function(cmd, _, done)
  if vim.tbl_contains(cmd, '--resolve-editions') then
    done { code = 0, stdout = vim.json.encode {
      editions = { 'B' }, names = { B = 'De Brug' }, has_explicit_editions = true,
    }, stderr = '' }
  else
    assert(not vim.tbl_contains(cmd, '--calendar'), 'onverwachte kalender-AI')
    metadata_calls = metadata_calls + 1
    done { code = 0, stdout = '---\nshort_title: Concert\n---\n', stderr = '' }
  end
  return { kill = function() error('losse AI-taak gestopt') end }
end
ai._agenda_duplicate_candidates = function(_, _, done)
  reviews = reviews + 1
  done { version = 1, performed = true, candidates = { { editie = 'B', bestaand_titel = 'Concert' } } }
end
ai._agenda_duplicate_confirm = function(_, _, done) answer = done end
ai._start_calendar_analysis = function() starts = starts + 1 end
local function run(extra, header)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  local document = (header or 'e: B') .. '\n\n=== ARTIKEL ===\n\n' .. body .. (extra or '')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(document, '\n', { plain = true }))
  ai._mark_duplicate_check_done(buf)
  vim.b[buf].calendar_ai_started = true -- eerdere herkenning leverde geen blok op
  answer = nil
  ai._post_full_article_rewrite {
    buf = buf, document = document, body = body, controls = { 'e: B' }, original_content = document,
  }
  return buf
end
local function wait(test) assert(vim.wait(2000, test, 5), 'herschrijfvervolg bleef wachten') end
local buf = run()
wait(function() return answer ~= nil end)
assert(starts == 0, 'kalender-AI startte vóór doublurebeoordeling')
answer(true)
assert(starts == 1, 'eerdere niet-herkenning blokkeerde latere herkenning')

buf = run()
wait(function() return answer ~= nil end)
answer(false)
assert(starts == 1, 'geen agenda gekozen maar AI startte toch')
assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('agenda: nee', 1, true))

buf = run()
wait(function() return answer ~= nil end)
answer(nil)
assert(starts == 1 and vim.b[buf].agenda_review_cancelled == true,
  'vraag sluiten liet automatisch alsnog agenda maken')

local before = reviews
local before_meta = metadata_calls
buf = run('\n\n## Kalender\n\nTitel: Eigen tekst\n', 'e: B\nagenda: ja')
wait(function() return (vim.b[buf].pending_jobs or 0) == 0 end)
assert(reviews == before and starts == 1, 'bestaande kalender werd opnieuw gemaakt')
assert(metadata_calls == before_meta + 1, 'bestaande agenda blokkeerde gewone artikelmetadata')
vim.system = original_system
print('calendar after rewrite: OK')
