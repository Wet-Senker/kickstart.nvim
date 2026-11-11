-- Exercise the real aw callback: explicit consent, one retry, no lost edits.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/werk', 'p')
vim.env.TEXTTOOLS_INBOX_DIR = directory
local ai = require('ai_text')
local recognition = require('article_recognition')
recognition.evaluate = function() return {} end
recognition.rubric_decision = function() return {} end
local dialog = require('user_dialog')
local old_select, old_system = dialog.select, vim.system
local codes = { 'B', 'SW', 'ST', 'Z', 'D', 'K' }
local serial = 0

local function run_case(choice, edits, offered)
  serial = serial + 1
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, directory .. '/werk/artikel-' .. serial .. '.md')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    'e: ' .. table.concat(codes, ', '), 'agenda: nee', '', '=== ARTIKEL ===',
    '', 'Kop', '', 'KAMPEN - Nieuws zonder evenementdatum.',
  })
  vim.b[buf].publication_review_state = { editions = codes, display_dates = {}, skip_newspaper_editions = codes }
  ai._mark_duplicate_check_done(buf)
  require('publication_dates').review = function(_, _, _, _, done) done('ready') end
  local calls, questions, callback, file = 0, 0
  dialog.select = function(items, opts, done)
    questions = questions + 1
    assert(opts.source_buf == buf and items[1]:find('standaarduitsnede', 1, true))
    if edits then
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere gebruikerszin.' })
    end
    done(choice == 1 and items[1] or nil, choice)
  end
  vim.system = function(command, _, done)
    assert(command[1]:match('pubble%-send$'), 'unexpected external action')
    calls = calls + 1
    assert(vim.tbl_contains(command, '--standard-photo-processing') == (calls == 2),
      'bypass is missing, implicit, or leaked from another send')
    file, callback = command[2], done
    if calls == 1 then
      local saved = { '---', 'newspaper:', '  article_join_id: 123',
        'web:', '  internet_article_ids: {B: 456}', '---', '' }
      vim.list_extend(saved, vim.fn.readfile(file))
      vim.fn.writefile(saved, file)
    else
      assert(table.concat(vim.fn.readfile(file), '\n'):find('B: 456', 1, true), 'retry lost existing IDs')
      vim.schedule(function() done({ code = 1, stdout = '', stderr = 'ordinary retry failure' }) end)
    end
    return { kill = function() end }
  end
  ai.pubble_send(buf)
  assert(calls == 1 and callback)
  callback({ code = 1, stderr = '', stdout = 'PUBBLE_RESULT_JSON: ' .. vim.json.encode({
    mode = 'failed', outcome = 'failed', phases = {
      { name = 'media', status = 'failed', recovery = offered and {
        action = 'use_standard_photo_processing', title = 'Foto-uitsnede mislukt', message = 'Alleen deze verzending.',
      } or nil },
    },
  }) })
  assert(vim.wait(1500, function() return vim.b[buf].publication_in_progress == false end), 'send remained locked')
  assert(questions == (offered and 1 or 0), 'wrong number of questions')
  assert(calls == ((offered and choice == 1 and not edits) and 2 or 1), 'unexpected retry')
  if edits then
    assert(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Nieuwere gebruikerszin.', 1, true),
      'late callback overwrote user edits')
  end
  assert(vim.b[buf].failed_send_file == file, 'recovery state was lost')
end

run_case(1, false, true)
run_case(2, false, true)
run_case(nil, false, true) -- Escape never grants permission.
run_case(1, true, true)
run_case(1, false, false) -- An ordinary upload/link error has no crop bypass.
dialog.select, vim.system = old_select, old_system
vim.fn.delete(directory, 'rf')
print('photo processing recovery: OK')
