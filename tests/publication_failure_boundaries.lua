-- Echte clientroute; uitsluitend gemockte subprocessen en tijdelijke bestanden.
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = root
local ai = require('ai_text')
local recovery = require('publication_recovery')
local jobs = require('buffer_jobs')
local recognition = require('article_recognition')
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end
local function drain()
  local done = false
  vim.schedule(function() vim.schedule(function() done = true end) end)
  assert(vim.wait(1000, function() return done end))
end
local original_system = vim.system
local buf = vim.api.nvim_create_buf(true, false)
local text = { '=== ARTIKEL ===', '', 'Kop', '', 'Mijn tekst.' }
vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
local attempts = 0
vim.system = function() attempts = attempts + 1; error('bewuste startfout') end
for _ = 1, 2 do
  vim.b[buf].cached_metadata = { '---', 'newspaper: {working_title: Kop}', '---' }
  vim.b[buf].cached_metadata_source = table.concat(text, '\n')
  ai.pubble_send(buf)
  drain()
  assert(not vim.b[buf].metadata_merge_pending and jobs.count(buf) == 0, 'metadata-startfout houdt poort dicht')
end
assert(attempts == 2, 'opnieuw proberen na startfout werkt niet')

local codes = { 'B', 'SW', 'ST', 'Z', 'D', 'K' }
local function run_case(kind)
  local file = root .. '/werk/' .. kind .. '.md'
  local lines = { 'e: ' .. table.concat(codes, ', '), 'agenda: nee', '',
    '=== ARTIKEL ===', '', 'Kop', '', 'KAMPEN - Nieuws.' }
  vim.fn.writefile(lines, file)
  local target = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(target, file)
  vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
  local source_name = vim.api.nvim_buf_get_name(target)
  vim.b[target].publication_review_state = { editions = codes, display_dates = {}, skip_newspaper_editions = codes }
  ai._mark_duplicate_check_done(target)
  require('publication_dates').review = function(_, _, _, _, done) done('ready') end
  require('layout_export').finalize_with_media = function(_, _, done) done(nil) end
  local callback, status_file, calls = nil, nil, 0
  local archive = root .. '/published-' .. kind .. '.md'
  local native_write, native_read = vim.fn.writefile, vim.fn.readfile
  local native_delete_source = ai._delete_source_file
  if kind == 'cleanup_exception' then ai._delete_source_file = function() error('cleanupfout') end end
  if kind == 'marker_write' then
    vim.fn.writefile = function(value, path, ...)
      if path:find('.pubble-recovery.json', 1, true) then error('schijffout') end
      return native_write(value, path, ...)
    end
  end
  vim.system = function(command, options, done)
    if command[1]:match('pubble%-send$') then
      calls = calls + 1
      assert(vim.fn.filereadable(source_name .. '.pubble-recovery.json') == 1,
        'externe write gestart zonder duurzame herstelbinding')
      if kind == 'main_start' then error('startfout') end
      status_file, callback = command[2], done
      local with_ids = { '---', 'newspaper: {article_join_id: 123}',
        'web: {internet_article_ids: {B: 456, SW: 457, ST: 458, Z: 459, D: 460, K: 461}}', '---', '' }
      vim.list_extend(with_ids, native_read(status_file))
      native_write(with_ids, status_file)
      return {}
    end
    assert(command[3] == 'texttools.pubble_archive' and type(done) == 'function' and options.timeout == 60000,
      'archivering moet asynchroon en begrensd zijn')
    assert(vim.tbl_contains(command, '--keep-source'), 'transactionele bron moet behouden blijven')
    if kind == 'archive_start' then error('startfout archiver') end
    if kind == 'archive_timeout' then
      vim.schedule(function() done({ code = 124, stdout = '', stderr = 'time-out' }) end)
    else
      native_write(native_read(status_file), archive)
      if kind == 'completion_write' then
        vim.fn.writefile = function(value, path, ...)
          if path:find('.pubble-recovery.json', 1, true) then error('schijffout') end
          return native_write(value, path, ...)
        end
      end
      local archive_path = kind == 'archive_empty_path' and ''
        or kind == 'archive_missing_path' and (root .. '/ontbreekt.md') or archive
      vim.schedule(function() done({ code = 0, stdout = kind == 'archive_bad_json' and 'geen JSON'
        or vim.json.encode({ path = archive_path }) }) end)
    end
    return {}
  end
  ai.pubble_send(target)
  if kind == 'marker_write' then
    vim.fn.writefile = native_write
    assert(calls == 0 and not vim.b[target].publication_in_progress, 'schijffout startte externe create')
    return
  end
  if kind == 'main_start' then
    drain()
    assert(not vim.b[target].publication_in_progress and vim.b[target].failed_send_file,
      'startfout laat verzending hangen of verliest statusbestand')
    return
  end
  if kind == 'closed' then
    vim.api.nvim_buf_delete(target, { force = true })
    -- Ook vóór het late resultaat mag een heropende bron geen tweede run starten.
    target = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(target, source_name)
    vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
    assert(recovery.review_conflict(target), 'lopende run niet beschermd na bufferverwijdering')
  elseif kind == 'read_error' then
    vim.fn.readfile = function(path, ...)
      if path == status_file then error('IO-fout') end
      return native_read(path, ...)
    end
  end
  callback({ code = kind == 'read_error' and 1 or 0, signal = 0, stderr = '', stdout =
    'PUBBLE_RESULT_JSON: ' .. vim.json.encode({ mode = 'published', outcome = 'success',
      phases = { { name = 'web', status = 'succeeded' } } }) })
  drain()
  vim.fn.readfile, vim.fn.writefile = native_read, native_write
  ai._delete_source_file = native_delete_source
  if kind ~= 'closed' then
    assert(not vim.b[target].publication_in_progress, 'verzendpoort bleef dicht: ' .. kind)
    assert(kind == 'cleanup_exception' or vim.b[target].failed_send_file, 'herstelbestand ontbreekt: ' .. kind)
  end
  if kind == 'read_error' then assert(vim.b[target].failed_send_conflict, 'leesfout mist blokkade') end
  if kind == 'cleanup_exception' then
    assert(vim.fn.filereadable(file) == 1 and vim.b[target].failed_send_conflict.completed,
      'cleanupfout na commit werd ten onrechte een nieuwe herstel-send')
  else
    assert(vim.fn.filereadable(status_file) == 1, 'ID-bron verdwenen vóór duurzame voltooiing')
  end
  require('user_dialog').confirm = function() return 2 end
  vim.b[target].failed_send_file = nil
  vim.b[target].failed_send_conflict = nil
  assert(recovery.review_conflict(target), 'heropenen mist duurzame blokkade: ' .. kind)
  ai.pubble_send(target)
  assert(calls == 1, 'heropenen startte een verse create: ' .. kind)
end
for _, kind in ipairs({ 'marker_write', 'main_start', 'closed', 'read_error', 'archive_start',
  'archive_timeout', 'archive_bad_json', 'archive_empty_path', 'archive_missing_path',
  'completion_write', 'cleanup_exception' }) do run_case(kind) end
-- Ook een rechtstreeks geopend statusbestand met een self-marker kan veilig
-- worden hervat: gebruik exact dat bestand en nooit een verse ID-loze bron.
local self_file = root .. '/self.md'
vim.fn.writefile({ '---', 'web: {internet_article_ids: {B: 456}}', '---', 'Tekst.' }, self_file)
local self_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(self_buf, self_file)
local attempt = recovery.begin_attempt(self_buf, self_file)
assert(attempt and recovery.review_conflict(self_buf), 'self-run moet tijdens werk blokkeren')
recovery.end_attempt(attempt)
assert(not recovery.review_conflict(self_buf) and vim.b[self_buf].failed_send_file == self_file,
  'self-marker verhindert veilig hervatten vanuit het statusbestand')
vim.system = original_system
vim.fn.delete(root, 'rf')
print('publication failure boundaries: OK')
