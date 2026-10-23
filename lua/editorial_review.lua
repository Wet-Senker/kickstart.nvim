-- Alleen presentatie en revisiebeveiliging. Python bepaalt de controlepunten.
local M = {}
local notify = require('texttools_notify')
local serial = 0

function M.valid_report(report, source)
  if type(report) ~= 'table' or report.version ~= 1
      or (report.status ~= 'ready' and report.status ~= 'needs_review')
      or type(report.article) ~= 'string' or vim.trim(report.article) == ''
      or report.source_sha256 ~= vim.fn.sha256(source)
      or type(report.issues) ~= 'table' or not vim.islist(report.issues) then return false end
  for _, issue in ipairs(report.issues) do
    if type(issue) ~= 'table' or type(issue.code) ~= 'string'
        or type(issue.message) ~= 'string' then return false end
  end
  return (report.status == 'ready') == (#report.issues == 0)
end

function M.open(options)
  serial = serial + 1
  local source_win = vim.fn.bufwinid(options.source_buf)
  local session = { buffers = {}, windows = {}, closed = false }
  local function buffer(role, lines, editable)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'texttools://an-review/' .. serial .. '/' .. role)
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = 'nofile', 'wipe', false
    vim.b[buf].texttools_proposal_review = true
    vim.bo[buf].filetype = 'markdown'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = editable
    session.buffers[#session.buffers + 1] = buf
    return buf
  end
  local function close()
    if session.closed then return end
    session.closed = true
    for _, win in ipairs(session.windows) do
      if vim.api.nvim_win_is_valid(win) then
        vim.wo[win].diff = false
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
    for _, buf in ipairs(session.buffers) do
      if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    end
    if source_win > 0 and vim.api.nvim_win_is_valid(source_win) then vim.api.nvim_set_current_win(source_win) end
  end
  function session.accept()
    if session.closed or not vim.api.nvim_buf_is_valid(session.proposal) then return end
    if not options.is_current() then
      notify.notify('Artikel gewijzigd of een nieuwere AN gestart. Dit voorstel is niet overgenomen. '
        .. 'Behoud het origineel en start opnieuw met <leader>an.', vim.log.levels.WARN)
      return
    end
    local lines = vim.api.nvim_buf_get_lines(session.proposal, 0, -1, false)
    if vim.trim(table.concat(lines, '\n')) == '' then
      notify.notify('Het voorstel is leeg. Pas het aan of behoud het origineel met q.', vim.log.levels.WARN)
      return
    end
    close()
    require('workflow_log').decision(options.source_buf, 'AN · Voorstel beoordelen', 'accepted')
    options.on_accept(lines)
  end
  function session.keep()
    if session.closed then return end
    close()
    require('workflow_log').decision(options.source_buf, 'AN · Voorstel beoordelen', 'kept_original')
  end
  local info = { 'Controleer de gemarkeerde verschillen; pas rechts zo nodig de tekst aan.',
    '<leader>aY / :ArtikelBewerkingOvernemen = overnemen   |   q / :ArtikelBewerkingBehouden = origineel behouden', '' }
  for _, issue in ipairs(options.report.issues) do
    vim.list_extend(info, vim.split(issue.message, '\n', { plain = true }))
  end
  vim.cmd('tabnew')
  session.tab = vim.api.nvim_get_current_tabpage()
  local header = buffer('controlepunten', info, false)
  vim.api.nvim_win_set_buf(0, header)
  session.windows[1] = vim.api.nvim_get_current_win()
  vim.wo.winbar = ' AN · Controlepunten · nog niets overgenomen'
  vim.cmd('belowright split')
  local left = buffer('onbewerkt', options.original, false)
  vim.api.nvim_win_set_buf(0, left)
  session.windows[2] = vim.api.nvim_get_current_win()
  vim.wo.winbar = ' Onbewerkt — oorspronkelijke tekst'
  vim.cmd('diffthis')
  vim.cmd('rightbelow vsplit')
  session.proposal = buffer('bewerkt', vim.split(options.report.article, '\n', { plain = true }), true)
  vim.api.nvim_win_set_buf(0, session.proposal)
  session.windows[3] = vim.api.nvim_get_current_win()
  vim.wo.winbar = ' Bewerkt — voorstel ter controle'
  vim.cmd('diffthis')
  vim.api.nvim_win_set_height(session.windows[1], math.min(#info, 8))
  for _, win in ipairs(session.windows) do
    vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].wrap = true, false, true
  end
  for _, buf in ipairs(session.buffers) do
    vim.keymap.set('n', '<leader>aY', session.accept, { buffer = buf, desc = 'Bewerkt voorstel overnemen' })
    vim.keymap.set('n', 'q', session.keep, { buffer = buf, desc = 'Origineel behouden' })
    vim.api.nvim_buf_create_user_command(buf, 'ArtikelBewerkingOvernemen', session.accept, {})
    vim.api.nvim_buf_create_user_command(buf, 'ArtikelBewerkingBehouden', session.keep, {})
  end
  return session
end

return M
