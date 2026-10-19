-- Echte aw-succesroute, zonder AI/CMS: bewaak elke asynchrone grens tot cleanup.
package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = directory
local ai = require('ai_text')
local recovery = require('publication_recovery')
local recognition = require('article_recognition')
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end
local codes = { 'B', 'SW', 'ST', 'Z', 'D', 'K' }
local serial = 0
local function run_case(stage)
  serial = serial + 1
  local file = directory .. '/werk/artikel-' .. serial .. '.md'
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, file)
  local original = { 'e: ' .. table.concat(codes, ', '), 'agenda: nee', '',
    '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Nieuws zonder evenementdatum.' }
  vim.fn.writefile(original, file)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
  vim.b[buf].publication_review_state = {
    editions = codes, display_dates = {}, skip_newspaper_editions = codes,
  }
  ai._mark_duplicate_check_done(buf)
  local newer
  local function change()
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 'c: Nieuwere fotograaf', 'Facebook: x' })
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { '', '## Kalender', '', 'Titel: Nieuw item' })
    newer = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  require('publication_dates').review = function(_, _, _, _, done)
    if stage == 'preparation' then change() end
    done('ready')
  end
  local export_done
  require('layout_export').finalize_with_media = function(_, _, done) export_done = done end
  local calls, callback, sending_file = {}, nil, nil
  local archive = directory .. '/archief-' .. serial .. '.md'
  local old_system = vim.system
  vim.system = function(command, _, done)
    table.insert(calls, command)
    if command[1]:match('pubble%-send$') then
      assert(vim.tbl_contains(command, '--create'))
      sending_file, callback = command[2], done
      return { kill = function() end }
    end
    assert(command[3] == 'texttools.pubble_archive', 'onverwachte extra call')
    assert(type(done) == 'function', 'archiveren blokkeert de editor')
    vim.schedule(function()
      if stage == 'archiving' then change() end
      vim.fn.writefile(vim.fn.readfile(sending_file), archive)
      assert(vim.tbl_contains(command, '--keep-source'), 'ID-bron mag niet vóór de voltooiingsmarker verdwijnen')
      done({ code = 0, stdout = vim.json.encode({ path = archive }) })
    end)
    return {}
  end
  local hooks = 0
  ai.set_publication_success_hook(buf, function() hooks = hooks + 1 end)
  ai.pubble_send(buf)
  assert(#calls == 1 and callback, 'send niet eenmaal gestart')
  if stage == 'sending' then change() end
  callback({ code = 0, signal = 0, stderr = '', stdout = 'PUBBLE_RESULT_JSON: '
    .. vim.json.encode({ mode = 'published', outcome = 'success', phases = {
      { name = 'web', status = 'succeeded' },
    } }) })
  assert(vim.wait(1000, function() return export_done ~= nil end), 'export niet bereikt')
  if stage == 'export' then change() end
  export_done(nil)
  assert(vim.wait(1000, function() return vim.b[buf].publication_in_progress == false end))
  assert(#calls == 2 and hooks == 1, 'extra calls of ontbrekende succes-hook')
  if stage then
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), newer),
      'nieuwere tekst/agenda/controleregels gewijzigd: ' .. stage)
    assert(vim.bo[buf].modified and vim.bo[buf].modifiable and not vim.bo[buf].readonly)
    assert(vim.fn.filereadable(file) == 1, 'werkbestand verwijderd: ' .. stage)
    require('user_dialog').confirm = function() return 2 end
    -- Ook na verlies van vluchtige b:-state blokkeert aw vóór ieder subprocess.
    vim.b[buf].failed_send_conflict = nil
    ai.pubble_send(buf)
    assert(#calls == 2 and recovery.review_conflict(buf), 'duplicaat mogelijk: ' .. stage)
  else
    assert(vim.fn.filereadable(file) == 0 and vim.bo[buf].buftype == 'nofile',
      'normale afronding veranderd')
  end
  assert(vim.fn.filereadable(archive) == 1, 'gepubliceerde versie ontbreekt')
  vim.system = old_system
end
run_case(nil)
run_case('preparation')
run_case('sending')
run_case('export')
run_case('archiving')
vim.fn.delete(directory, 'rf')
print('publication success edits: OK')
