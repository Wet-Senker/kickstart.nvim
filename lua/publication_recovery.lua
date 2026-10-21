-- UI-grens voor late publicatieresultaten. Geen merge van domeinstate: bij
-- gelijktijdige edits blijven beide documenten apart ter menselijke review.
local M = {}
local notifications = require('texttools_notify')
local log = require('workflow_log')
local paths = require('texttools_paths')
local revisions = require('buffer_revision')
local layout_export = require('layout_export')
local running = {}
local questions = {}
local function canonical(file) return vim.fn.resolve(vim.fn.fnamemodify(file, ':p')) end

local function ask(buf, prompt, buttons, done)
  if questions[buf] then return end
  local request = {}
  questions[buf] = request
  require('user_dialog').confirm_async(prompt, buttons, 1, false, notifications.bind(buf, function(choice)
    if questions[buf] ~= request then return end
    questions[buf] = nil
    if not vim.api.nvim_buf_is_valid(buf) then return end
    done(choice)
  end), { source_buf = buf })
end

local function marker_path(buf)
  local existing = vim.b[buf].publication_recovery_marker
  if type(existing) == 'string' and existing ~= '' then return existing end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or name:find('://', 1, true) then return nil end
  return name .. '.pubble-recovery.json'
end

local function write_marker(path, record)
  if not path then return false end
  local temporary = path .. '.tmp-' .. vim.fn.getpid()
  local ok = pcall(function()
    assert(vim.fn.writefile({ vim.json.encode(record) }, temporary) == 0)
    assert(vim.fn.rename(temporary, path) == 0)
  end)
  return ok
end

local function save_marker(buf, record)
  record.layout_export = layout_export.pending(buf)
  local path = marker_path(buf)
  local ok = write_marker(path, record)
  if ok then vim.b[buf].publication_recovery_marker = path else
    log.diagnostic(buf, 'Publicatie · Herstel', { status = 'failed', reason = 'recovery_marker_write_failed' })
    notifications.workflow('De herstelverwijzing kon niet op schijf worden bewaard. Laat deze buffer open en beoordeel eerst het herstelbestand.', vim.log.levels.ERROR)
  end
  return ok
end

-- Clientbinding: vóór iedere externe write moet de bron naar exact het
-- statusbestand verwijzen. Geen domeinstate of ID-merge in de editor.
function M.begin_attempt(buf, file)
  local path = marker_path(buf) or (file .. '.pubble-recovery.json')
  if running[canonical(file)] then return nil end
  if not write_marker(path, { version = 1, completed = false,
      recovery_name = vim.fn.fnamemodify(file, ':t'), layout_export = layout_export.pending(buf) }) then
    notifications.workflow('Verzending gestopt: de herstelverwijzing kon niet worden opgeslagen. Er is niets naar Pubble gestuurd.', vim.log.levels.ERROR)
    return nil
  end
  local attempt = { marker = path, file = file, buf = buf }
  vim.b[buf].publication_recovery_marker = path
  running[canonical(file)] = attempt
  return attempt
end

function M.end_attempt(attempt)
  if attempt and running[canonical(attempt.file)] == attempt then running[canonical(attempt.file)] = nil end
end

function M.release_unpublished(buf, file)
  if running[canonical(file)] then return false end
  local path = marker_path(buf)
  if not path or vim.fn.filereadable(path) ~= 1 then return true end
  local ok, record = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(path), '\n')) end)
  if not ok or record.completed or record.recovery_name ~= vim.fn.fnamemodify(file, ':t') then return false end
  if vim.fn.delete(path) ~= 0 then return false end
  vim.b[buf].publication_recovery_marker = nil
  return true
end

-- Ook na heropenen van de oude bron mag aw niet voorbij de bewaarde ID-state.
local function load_conflict(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or name:find('://', 1, true) then return nil end
  -- Een herstelbuffer erft de marker alleen om die na succes te kunnen
  -- afronden. Die marker blokkeert uitsluitend de oude bron, niet de retry.
  local path = name .. '.pubble-recovery.json'
  if not path or vim.fn.getftype(path) == '' then return nil end
  local ok, record = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path, '', 32), '\n'))
  end)
  vim.b[buf].publication_recovery_marker = path
  if not ok or type(record) ~= 'table' or record.version ~= 1 then return { invalid = true } end
  if record.layout_export ~= nil and not layout_export.valid_plan(record.layout_export) then
    return { invalid = true }
  end
  if record.completed == true then
    local archive = record.archive_path
    if archive ~= nil and (type(archive) ~= 'string' or not archive:match('^/.*%.md$')) then
      return { invalid = true }
    end
    return { completed = true, archive_path = archive }
  end
  local name = record.recovery_name
  if type(name) ~= 'string' or name == '' or vim.fn.fnamemodify(name, ':t') ~= name
      or not name:match('%.md$') then return { invalid = true } end
  return { file = paths.inbox() .. '/' .. name, layout_export = record.layout_export }
end

function M.preserve_published_edits(buf, archive_path)
  vim.b[buf].failed_send_conflict = { completed = true, archive_path = archive_path }
  vim.b[buf].published_archive_path = archive_path
  save_marker(buf, { version = 1, completed = true, archive_path = archive_path })
  log.diagnostic(buf, 'Publicatie · Herstel', { status = 'blocked', reason = 'published_buffer_changed' })
end

function M.restore(buf, file, expected_tick, keep_file)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if keep_file then vim.b[buf].failed_send_file = file end
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then
    vim.b[buf].failed_send_conflict = { file = file }
    save_marker(buf, { version = 1, completed = false, recovery_name = vim.fn.fnamemodify(file, ':t') })
    log.diagnostic(buf, 'Publicatie · Herstel', { status = 'failed', reason = 'recovery_file_missing' })
    notifications.workflow('Herstelbestand kon niet worden gelezen; de huidige tekst is behouden.', vim.log.levels.ERROR)
    return false
  end
  if not revisions.matches(buf, expected_tick) then
    -- Cruciaal: ook de volgende aw mag deze ID-state niet opnieuw met de
    -- actuele, maar ID-loze bron overschrijven.
    vim.b[buf].failed_send_file = file
    vim.b[buf].failed_send_conflict = { file = file }
    save_marker(buf, { version = 1, completed = false, recovery_name = vim.fn.fnamemodify(file, ':t') })
    log.diagnostic(buf, 'Publicatie · Herstel', { status = 'blocked', reason = 'buffer_changed' })
    notifications.workflow(
      'De tekst, agenda of fotokeuze is tijdens de verzending gewijzigd. '
        .. 'Niets in je buffer is overschreven. De Pubble-status is apart bewaard; '
        .. 'druk <leader>aw om het herstelbestand te openen en te vergelijken.',
      vim.log.levels.WARN
    )
    return false
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if keep_file then vim.b[buf].failed_send_file = file end
  vim.b[buf].publication_recovery_synced_tick = vim.api.nvim_buf_get_changedtick(buf)
  vim.b[buf].publication_recovery_synced_revision = revisions.capture(buf)
  log.diagnostic(buf, 'Publicatie · Herstel', { status = 'ready', reason = 'unchanged_buffer' })
  return true
end

-- true betekent: deze aw is afgehandeld als review, er mag NIET verzonden
-- worden. Alleen het apart geopende, ID-bevattende herstelbestand mag hervatten.
function M.review_conflict(buf)
  if vim.bo[buf].buftype == 'nofile' and vim.b[buf].published_archive_path then
    notifications.workflow('Dit is een alleen-lezen gepubliceerde versie; opnieuw verzenden is geblokkeerd.', vim.log.levels.WARN)
    return true
  end
  local conflict = load_conflict(buf) or vim.b[buf].failed_send_conflict
  local name = vim.api.nvim_buf_get_name(buf)
  if (name ~= '' and running[canonical(name)])
      or (type(conflict) == 'table' and conflict.file and running[canonical(conflict.file)]) then
    notifications.workflow('Deze publicatierun wordt nog afgehandeld. Wacht op afronding; er wordt niets opnieuw verstuurd.', vim.log.levels.INFO)
    return true
  end
  if type(conflict) ~= 'table' then return false end
  if conflict.file and name ~= '' and not name:find('://', 1, true)
      and canonical(conflict.file) == canonical(name) and vim.fn.filereadable(conflict.file) == 1 then
    -- Een naamloze start kan alleen haar statusbestand als heropeningang
    -- bewaren. Dat bestand is zelf de autoriteit, niet een ID-loze oude bron.
    vim.b[buf].failed_send_file = conflict.file
    vim.b[buf].failed_send_conflict = nil
    return false
  end
  if conflict.file and not vim.b[buf].failed_send_conflict
      and vim.b[buf].failed_send_file == conflict.file
      and revisions.matches(buf, vim.b[buf].publication_recovery_synced_revision
        or vim.b[buf].publication_recovery_synced_tick) then
    return false
  end
  if conflict.completed then
    vim.b[buf].failed_send_conflict = conflict
    local archive = conflict.archive_path
    if type(archive) == 'string' and vim.fn.filereadable(archive) == 1 then
      ask(buf,
        'Dit artikel is al gepubliceerd. Je nieuwere werk is niet meegepubliceerd. Open de gepubliceerde versie alleen-lezen om te vergelijken; er wordt niets verzonden.',
        '&Gepubliceerde versie openen\n&Annuleren', function(choice)
      if choice == 1 and vim.fn.filereadable(archive) == 1 then
        local target = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(target, 'pubble-nacontrole://' .. target .. '/' .. vim.fn.fnamemodify(archive, ':t'))
        vim.api.nvim_buf_set_lines(target, 0, -1, false, vim.fn.readfile(archive))
        vim.b[target].published_archive_path = archive
        vim.bo[target].bufhidden = 'wipe'
        vim.bo[target].modified = false
        vim.bo[target].readonly = true
        vim.bo[target].modifiable = false
        vim.cmd('botright vsplit')
        vim.api.nvim_win_set_buf(0, target)
      end
      end)
    else
      notifications.workflow('Deze werkversie is al gepubliceerd. Gebruik het Pubble-archief; verzend dit exemplaar niet opnieuw.', vim.log.levels.WARN)
    end
    return true
  end
  if conflict.invalid then
    notifications.workflow('De opgeslagen herstelverwijzing is ongeldig. Controleer eerst de Pubble-status; er is niets verzonden.', vim.log.levels.ERROR)
    return true
  end
  vim.b[buf].failed_send_conflict = conflict
  local file = conflict.file
  if type(file) ~= 'string' or vim.fn.filereadable(file) ~= 1 then
    notifications.workflow('Het herstelbestand is niet meer beschikbaar. De huidige tekst blijft behouden; verzend niet opnieuw zonder de Pubble-status te controleren.', vim.log.levels.ERROR)
    return true
  end
  vim.b[buf].failed_send_file = file
  ask(buf,
    'Je nieuwste werk en de Pubble-herstelstatus verschillen. Open het herstelbestand apart; kopieer daarin zo nodig je nieuwere tekst, agenda of fotokeuze vóór je hervat.',
    '&Herstelbestand openen\n&Annuleren', function(choice)
  if choice ~= 1 then return end
  if vim.fn.filereadable(file) ~= 1 then
    notifications.workflow('Het herstelbestand is niet meer beschikbaar. Controleer de Pubble-status vóór je opnieuw verzendt.', vim.log.levels.ERROR)
    return
  end
  local target = vim.fn.bufnr(file)
  if target >= 0 and vim.fn.bufloaded(target) == 1 and vim.bo[target].modified then
    -- Een eerder geopende herstelbuffer kan óók nieuwere edits bevatten.
    -- Lees de duurzame status daarom apart, nooit over die buffer heen.
    target = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(target, 'pubble-herstel://' .. vim.fn.fnamemodify(file, ':t') .. '/' .. target)
    vim.bo[target].buftype = 'nofile'
    vim.bo[target].bufhidden = 'hide'
    vim.api.nvim_buf_set_lines(target, 0, -1, false, vim.fn.readfile(file))
  else
    target = vim.fn.bufadd(file)
    vim.fn.bufload(target)
    -- Een al geladen maar ongewijzigde buffer kan een oudere diskversie tonen.
    vim.api.nvim_buf_set_lines(target, 0, -1, false, vim.fn.readfile(file))
  end
  vim.b[target].failed_send_file = file
  vim.b[target].publication_recovery_marker = vim.b[buf].publication_recovery_marker
  -- Dit is een client-uitvoerplan, geen Pubble-ID-merge. Neem ook het
  -- duurzame plan mee wanneer de oorspronkelijke sessie al gesloten is.
  vim.b[target].gn_export = layout_export.pending(buf) or conflict.layout_export
  for _, key in ipairs({
    'publication_review_state', 'event_review_state', 'skip_newspaper_editions',
    'late_newspaper_decision', 'send_import_body', 'send_ai_rewrite_completed',
    'send_ai_neutrality_body_hash', 'send_safeguard_approved_body',
    'krant_template', 'recognized_rubric',
  }) do
    vim.b[target][key] = vim.b[buf][key]
  end
  vim.cmd('botright vsplit')
  vim.api.nvim_win_set_buf(0, target)
  notifications.workflow('Herstelbestand geopend. Behoud de Pubble-ID’s bovenaan; neem je gewenste wijzigingen over en hervat hier met <leader>aw.', vim.log.levels.INFO)
  end)
  return true
end

function M.complete(buf, archive_path)
  if vim.b[buf].publication_recovery_marker then
    -- Laat bij de bewaarde oude bron een permanente blokkade staan. Zo maakt
    -- die na herstart geen nieuw artikel wanneer het ID-bestand is gearchiveerd.
    return save_marker(buf, { version = 1, completed = true, archive_path = archive_path })
  end
  return true
end

return M
