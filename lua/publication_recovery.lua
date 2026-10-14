-- UI-grens voor late publicatieresultaten. Geen merge van domeinstate: bij
-- gelijktijdige edits blijven beide documenten apart ter menselijke review.
local M = {}
local notifications = require('texttools_notify')
local log = require('workflow_log')
local paths = require('texttools_paths')

local function marker_path(buf)
  local existing = vim.b[buf].publication_recovery_marker
  if type(existing) == 'string' and existing ~= '' then return existing end
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or name:find('://', 1, true) then return nil end
  return name .. '.pubble-recovery.json'
end

local function save_marker(buf, record)
  local path = marker_path(buf)
  if not path then return end -- Een naamloze scratchbuffer heeft geen heropenpad.
  local temporary = path .. '.tmp-' .. vim.fn.getpid()
  local ok = pcall(function()
    assert(vim.fn.writefile({ vim.json.encode(record) }, temporary) == 0)
    assert(vim.fn.rename(temporary, path) == 0)
  end)
  if ok then
    vim.b[buf].publication_recovery_marker = path
  else
    log.diagnostic(buf, 'Publicatie · Herstel', { status = 'failed', reason = 'recovery_marker_write_failed' })
    notifications.workflow('De herstelverwijzing kon niet op schijf worden bewaard. Laat deze buffer open en beoordeel eerst het herstelbestand.', vim.log.levels.ERROR)
  end
end

-- Ook na heropenen van de oude bron mag aw niet voorbij de bewaarde ID-state.
local function load_conflict(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == '' or name:find('://', 1, true) then return nil end
  -- Een herstelbuffer erft de marker alleen om die na succes te kunnen
  -- afronden. Die marker blokkeert uitsluitend de oude bron, niet de retry.
  local path = name .. '.pubble-recovery.json'
  if not path or vim.fn.filereadable(path) ~= 1 then return nil end
  local ok, record = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path, '', 32), '\n'))
  end)
  vim.b[buf].publication_recovery_marker = path
  if not ok or type(record) ~= 'table' or record.version ~= 1 then return { invalid = true } end
  if record.completed == true then return { completed = true } end
  local name = record.recovery_name
  if type(name) ~= 'string' or name == '' or vim.fn.fnamemodify(name, ':t') ~= name
      or not name:match('%.md$') then return { invalid = true } end
  return { file = paths.inbox() .. '/' .. name }
end

function M.restore(buf, file, expected_tick, keep_file)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then
    log.diagnostic(buf, 'Publicatie · Herstel', { status = 'failed', reason = 'recovery_file_missing' })
    notifications.workflow('Herstelbestand kon niet worden gelezen; de huidige tekst is behouden.', vim.log.levels.ERROR)
    return false
  end
  if vim.api.nvim_buf_get_changedtick(buf) ~= expected_tick then
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
  log.diagnostic(buf, 'Publicatie · Herstel', { status = 'ready', reason = 'unchanged_buffer' })
  return true
end

-- true betekent: deze aw is afgehandeld als review, er mag NIET verzonden
-- worden. Alleen het apart geopende, ID-bevattende herstelbestand mag hervatten.
function M.review_conflict(buf)
  local conflict = load_conflict(buf) or vim.b[buf].failed_send_conflict
  if type(conflict) ~= 'table' then return false end
  if conflict.completed then
    notifications.workflow('Deze oude werkversie is al via het herstelbestand gepubliceerd. Gebruik het Pubble-archief; verzend dit exemplaar niet opnieuw.', vim.log.levels.WARN)
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
  local choice = require('user_dialog').confirm(
    'Je nieuwste werk en de Pubble-herstelstatus verschillen. Open het herstelbestand apart; kopieer daarin zo nodig je nieuwere tekst, agenda of fotokeuze vóór je hervat.',
    '&Herstelbestand openen\n&Annuleren', 1
  )
  if choice ~= 1 then return true end
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
  for _, key in ipairs({
    'publication_review_state', 'event_review_state', 'skip_newspaper_editions',
    'late_newspaper_decision', 'send_import_body', 'send_ai_rewrite_completed',
    'send_ai_neutrality_body_hash', 'send_safeguard_approved_body',
  }) do
    vim.b[target][key] = vim.b[buf][key]
  end
  vim.cmd('botright vsplit')
  vim.api.nvim_win_set_buf(0, target)
  notifications.workflow('Herstelbestand geopend. Behoud de Pubble-ID’s bovenaan; neem je gewenste wijzigingen over en hervat hier met <leader>aw.', vim.log.levels.INFO)
  return true
end

function M.complete(buf)
  if vim.b[buf].publication_recovery_marker then
    -- Laat bij de bewaarde oude bron een permanente blokkade staan. Zo maakt
    -- die na herstart geen nieuw artikel wanneer het ID-bestand is gearchiveerd.
    save_marker(buf, { version = 1, completed = true })
  end
end

return M
