-- De echte aw-flow, volledig gemockt: wijzigingen vóór én tijdens de externe
-- verzending moeten behouden blijven bij een deelfout, zonder extra calls.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
vim.fn.mkdir(directory .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = directory
local ai = require('ai_text')
local recovery = require('publication_recovery')
local recognition = require('article_recognition')
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end

local codes = { 'B', 'SW', 'ST', 'Z', 'D', 'K' }
local serial = 0
local function run_case(edit_stage)
  serial = serial + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, directory .. '/werk/artikel-' .. serial .. '.md')
  local original = {
    'e: ' .. table.concat(codes, ', '), 'agenda: nee', '', '=== ARTIKEL ===',
    '', 'Kop', '', 'KAMPEN - Nieuws zonder evenementdatum.',
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  vim.b[buf].publication_review_state = {
    editions = codes, display_dates = {}, skip_newspaper_editions = codes,
  }
  ai._mark_duplicate_check_done(buf)
  local function change()
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'c: Nieuwere fotokeuze' })
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, {
      '', '## Kalender', '', 'Titel: Nieuw agendapunt', 'Datum: 2026-10-20',
    })
  end
  require('publication_dates').review = function(_, _, _, _, done)
    if edit_stage == 'preparation' then change() end
    done('ready')
  end
  local calls, callback, file = 0
  local old_system = vim.system
  vim.system = function(command, _, done)
    assert(command[1]:match('pubble%-send$') and vim.tbl_contains(command, '--create'),
      'onverwachte AI/API/voorbereidingscall')
    calls = calls + 1
    file = command[2]
    callback = done
    local saved = {
      '---', 'newspaper:', '  article_join_id: 123',
      'web:', '  internet_article_ids: {B: 456, SW: 457, ST: 458, Z: 459, D: 460, K: 461}',
      '---', '',
    }
    vim.list_extend(saved, vim.fn.readfile(file))
    vim.fn.writefile(saved, file)
    return { kill = function() end }
  end
  local ok, err = pcall(ai.pubble_send, buf)
  assert(ok, err)
  assert(calls == 1 and callback, 'verzendfase niet exact eenmaal gestart')
  if edit_stage == 'sending' then change() end
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  callback({ code = 1, signal = 0, stderr = '', stdout = 'PUBBLE_RESULT_JSON: '
    .. vim.json.encode({ mode = 'published', outcome = 'failed', phases = {
      { name = 'web', status = 'succeeded' }, { name = 'media', status = 'failed' },
    } }) })
  assert(vim.wait(1000, function() return vim.b[buf].publication_in_progress == false end),
    'publicatiepoort bleef gesloten')
  vim.system = old_system
  if edit_stage then
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), current),
      'nieuwere agenda/foto ging verloren: ' .. edit_stage)
    assert(vim.b[buf].failed_send_conflict, 'ontbrekende retryblokkade: ' .. edit_stage)
    local marker = vim.b[buf].publication_recovery_marker
    assert(vim.fn.filereadable(marker) == 1, 'conflict verdwijnt na herstart')
    local saved = vim.json.decode(table.concat(vim.fn.readfile(marker), '\n'))
    assert(saved.version == 1 and saved.recovery_name == vim.fn.fnamemodify(file, ':t'),
      'herstelverwijzing mist bestand of versie')
    -- Simuleer nieuwe buffersessie: geen b:-state, nog steeds geen directe send.
    vim.b[buf].failed_send_conflict = nil
    vim.b[buf].failed_send_file = nil
    require('user_dialog').confirm = function() return 2 end
    assert(recovery.review_conflict(buf), 'heropenen omzeilde de ID-state')
    require('user_dialog').confirm = function() return 1 end
    assert(recovery.review_conflict(buf), 'review startte een verzending')
    local target = vim.api.nvim_get_current_buf()
    assert(not recovery.review_conflict(target), 'herstelbuffer erft bronblokkade')
    recovery.complete(target)
    vim.b[buf].failed_send_conflict = nil
    assert(recovery.review_conflict(buf), 'oude bron mag na succes opnieuw publiceren')
    saved = vim.json.decode(table.concat(vim.fn.readfile(marker), '\n'))
    assert(saved.completed == true, 'succesblokkade is niet duurzaam')
  else
    assert(not vim.b[buf].failed_send_conflict, 'ongewijzigde bron kreeg onnodig conflict')
    assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[3] == '  article_join_id: 123',
      'gewone herstelroute mist IDs')
  end
  assert(vim.b[buf].failed_send_file == file, 'duurzame state niet gekoppeld')
  assert(table.concat(vim.fn.readfile(file), '\n'):find('SW: 457', 1, true), 'editie-ID verdwenen')
  assert(calls == 1, 'fout startte onverwacht extra calls')
end
run_case(nil)
run_case('preparation')
run_case('sending')
vim.fn.delete(directory, 'rf')
print('publication recovery send: OK')
