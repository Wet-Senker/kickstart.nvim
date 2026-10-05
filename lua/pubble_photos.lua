-- Thin async client. Search rules, durable selection and metadata live in Python.
local M = {}
local commands = require 'texttools_commands'
local dialog = require 'user_dialog'
local notify = require('texttools_notify').workflow
local browser = require 'ordered_browser'
local sessions = {}

local function one_line(value)
  return tostring(value or ''):gsub('%c', ' ')
end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
end

local function current(s)
  return sessions[s.source] == s and not s.closed
    and vim.api.nvim_buf_is_valid(s.source)
    and vim.api.nvim_buf_get_changedtick(s.source) == s.tick
    and vim.b[s.source].publication_in_progress ~= true
end

local function run(s, args, input, done)
  if s.busy then return end
  s.busy = true
  local cmd = { commands.bin('python'), '-m', 'texttools.pubble_photo_cli' }
  vim.list_extend(cmd, args)
  local ok, err = pcall(vim.system, cmd, { text = true, stdin = input }, function(result)
    vim.schedule(function()
      s.busy = false
      s.process = nil
      if s.closed or sessions[s.source] ~= s then return end
      if not current(s) then
        notify('Artikel is intussen gewijzigd. Open de fotokeuze opnieuw; niets overschreven.', vim.log.levels.WARN)
        return
      end
      local decoded, data = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not decoded or type(data) ~= 'table' or data.version ~= 1 then
        notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
          or 'Fotokeuze mislukt; artikel is niet gewijzigd.', vim.log.levels.ERROR)
        return
      end
      done(data)
    end)
  end)
  if not ok then
    s.busy = false
    notify('Fotokeuze kon niet starten: ' .. tostring(err), vim.log.levels.ERROR)
  else
    s.process = err
  end
end

local function stop_browser(s)
  local previous = s.browser_choice
  s.browser_choice = nil
  if previous and previous.process and type(previous.process.kill) == 'function' then
    pcall(previous.process.kill, previous.process, 15)
  end
end

local function dispose(s)
  s.closed = true
  stop_browser(s)
  if sessions[s.source] == s then sessions[s.source] = nil end
  if s.input_win and vim.api.nvim_win_is_valid(s.input_win) then
    vim.api.nvim_win_close(s.input_win, true)
  end
  if s.busy and s.process and type(s.process.kill) == 'function' then
    pcall(s.process.kill, s.process, 15)
  end
end

local function close(s)
  dispose(s)
  if s.buffer and vim.api.nvim_buf_is_valid(s.buffer) then
    vim.api.nvim_buf_delete(s.buffer, { force = true })
  end
  if s.source_win and vim.api.nvim_win_is_valid(s.source_win)
      and vim.api.nvim_win_get_buf(s.source_win) == s.source then
    vim.api.nvim_set_current_win(s.source_win)
  end
end

local function selected(s)
  if not s.buffer or not vim.api.nvim_buf_is_valid(s.buffer) then return end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return s.rows[line]
end

local function choose(s, photo, confirmed)
  photo = photo or selected(s)
  if not photo or s.busy then return end
  if not current(s) then
    notify('Artikel is gewijzigd. Open de fotokeuze opnieuw.', vim.log.levels.WARN)
    return
  end
  local credit = photo.credit ~= '' and photo.credit or '(leeg — aanvullen in c:)'
  local caption = photo.caption ~= '' and photo.caption or '(leeg — aanvullen in b:)'
  if not confirmed and dialog.confirm('Deze foto gebruiken? Controleer context en gebruiksrechten.\n\n'
      .. photo.source_title .. '\nCredit: ' .. credit .. '\nBijschrift: ' .. caption,
      '&Ja\n&Nee', 2) ~= 1 then return end
  stop_browser(s)
  run(s, { 'select' }, vim.json.encode({ markdown = text(s.source), photo = photo }), function(data)
    if type(data.markdown) ~= 'string' then return end
    -- No callback may replace edits made after this request began.
    if not current(s) then return end
    local lines = vim.split(data.markdown:gsub('\n$', ''), '\n', { plain = true })
    vim.api.nvim_buf_set_lines(s.source, 0, -1, false, lines)
    local source = s.source
    close(s)
    vim.api.nvim_set_current_buf(source)
    local saved = true
    if vim.api.nvim_buf_get_name(source) ~= '' and vim.bo[source].buftype == '' then
      saved = pcall(vim.cmd, 'silent update')
    end
    notify(saved and 'Foto gekozen. Controleer b: (bijschrift) en c: (credit); daarna <leader>aw om te verzenden.'
      or 'Foto staat in de buffer, maar opslaan mislukte. Sla eerst op; controleer b: en c:, daarna <leader>aw.',
      saved and vim.log.levels.INFO or vim.log.levels.WARN, { ttl = 12 })
  end)
end

local function open_browser_choice(s)
  if s.busy or not current(s) then return end
  if not s.photos or #s.photos == 0 then
    notify('Geen foto’s op deze pagina. Zoek eerst met s of blader met ]p.', vim.log.levels.INFO)
    return
  end
  if s.browser_choice then
    if s.browser_choice.url then browser.open_urls({ s.browser_choice.url }) end
    return
  end
  local session = { pending = '' }
  s.browser_choice = session
  local function event(data)
    if s.browser_choice ~= session or s.closed then return end
    if not current(s) then
      stop_browser(s)
      notify('Artikel is gewijzigd; browserkeuze vervallen. Open de fotokeuze opnieuw.', vim.log.levels.WARN)
      return
    end
    if data.version ~= 1 then return end
    if data.event == 'ready' and type(data.url) == 'string'
        and data.url:match('^http://127%.0%.0%.1:%d+/[%w_-]+/$') then
      session.url = data.url
      if not browser.open_urls({ data.url }) then stop_browser(s) end
    elseif data.event == 'selected' then
      for _, photo in ipairs(s.photos) do
        if photo.image_metadata_id == data.image_metadata_id then
          -- The explicit browser button is the confirmation. The shared select
          -- action and source changedtick guard still apply; never auto-send.
          choose(s, photo, true)
          return
        end
      end
      stop_browser(s)
      notify('Deze browserkeuze hoort niet bij de huidige zoekpagina.', vim.log.levels.WARN)
    elseif data.event == 'expired' then
      stop_browser(s)
      notify('Foto-overzicht verlopen. Druk p voor een nieuw overzicht.', vim.log.levels.INFO)
    end
  end
  local cmd = { commands.bin('python'), '-m', 'texttools.pubble_photo_cli', 'browse' }
  local ok, process = pcall(vim.system, cmd, {
    text = true, stdin = vim.json.encode({ photos = s.photos }),
    stdout = function(err, chunk)
      if err or not chunk then return end
      session.pending = session.pending .. chunk
      while session.pending:find('\n', 1, true) do
        local ending = session.pending:find('\n', 1, true)
        local line = session.pending:sub(1, ending - 1)
        session.pending = session.pending:sub(ending + 1)
        local decoded, data = pcall(vim.json.decode, line)
        if decoded and type(data) == 'table' then vim.schedule(function() event(data) end) end
      end
    end,
  }, function(result)
    vim.schedule(function()
      if s.browser_choice ~= session then return end
      s.browser_choice = nil
      if result.code ~= 0 then
        notify('Browserkeuze kon niet worden geopend. Gebruik Enter in de fotolijst of probeer p opnieuw.', vim.log.levels.WARN)
      end
    end)
  end)
  if ok then session.process = process
  else
    s.browser_choice = nil
    notify('Browserkeuze kon niet starten. Gebruik Enter in de fotolijst.', vim.log.levels.WARN)
  end
end

local search
local function ask_query(s, initial)
  if s.busy or not current(s) then return end
  stop_browser(s)
  dialog.input({ prompt = 'Pubble-foto’s zoeken', default = initial or s.query or '', vim_edit = true,
    on_open = function(buf, win)
      s.input_win = win
      vim.b[buf].pubble_photo_source = s.source
    end,
  }, function(query)
    s.input_win = nil
    if not current(s) then
      if not s.closed then
        notify('Artikel is intussen gewijzigd. Open de fotokeuze opnieuw; niets overschreven.', vim.log.levels.WARN)
      end
      return
    end
    -- A pasted multi-line query is still one search. Python owns query rules.
    query = query and vim.trim(query:gsub('%s+', ' ')) or nil
    if query and query ~= '' then
      search(s, query, 0)
    elseif not s.buffer then
      close(s)
    end
  end)
end

local function render(s, data)
  if not s.buffer or not vim.api.nvim_buf_is_valid(s.buffer) then
    if s.source_win and vim.api.nvim_win_is_valid(s.source_win)
        and vim.api.nvim_win_get_buf(s.source_win) == s.source then
      vim.api.nvim_set_current_win(s.source_win)
    end
    vim.cmd('botright vsplit')
    s.buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, s.buffer)
    vim.bo[s.buffer].buftype = 'nofile'
    vim.bo[s.buffer].bufhidden = 'wipe'
    vim.bo[s.buffer].filetype = 'text'
    vim.b[s.buffer].pubble_photo_source = s.source
    vim.api.nvim_create_autocmd('BufWipeout', { buffer = s.buffer, once = true, callback = function()
      dispose(s)
    end })
    local function map(key, fn, desc)
      vim.keymap.set('n', key, fn, { buffer = s.buffer, silent = true, desc = desc })
    end
    map('<CR>', function() choose(s) end, 'Deze foto kiezen')
    map('o', function()
      local photo = selected(s)
      if photo then browser.open_urls({ photo.preview_url }) end
    end, 'Foto online bekijken')
    map('p', function() open_browser_choice(s) end, 'Alle voorbeelden in browser bekijken en kiezen')
    map('s', function() ask_query(s) end, 'Andere zoekwoorden')
    map(']p', function()
      if type(s.next_offset) == 'number' then search(s, s.query, s.next_offset) end
    end, 'Volgende resultaten')
    map('q', function() close(s) end, 'Terug zonder fotokeuze')
  end
  s.rows = {}
  s.photos = data.photos or {}
  local lines = { 'Pubble-foto’s · ' .. s.query,
    'o: foto | p: voorbeelden | Enter: kies | s: zoekwoorden | ]p: volgende pagina | q: terug',
    '112 uitgesloten. Controleer context en gebruiksrechten van de foto.', '' }
  for i, photo in ipairs(data.photos or {}) do
    local first = #lines + 1
    vim.list_extend(lines, {
      string.format('%d. %s [%s · %s]', i, one_line(photo.source_title), one_line(photo.edition), one_line(photo.date)),
      '   Bijschrift: ' .. (photo.caption ~= '' and one_line(photo.caption) or '(leeg)'),
      '   Credit: ' .. (photo.credit ~= '' and one_line(photo.credit) or '(leeg)'), '',
    })
    for row = first, #lines do s.rows[row] = photo end
  end
  if #(data.photos or {}) == 0 then table.insert(lines, 'Geen selecteerbare foto’s op deze pagina. Probeer s of ]p.') end
  if (data.excluded_articles or 0) > 0 or (data.unclassified_articles or 0) > 0 then
    table.insert(lines, string.format('Overgeslagen: %d 112-artikelen; %d artikelen zonder leesbare rubriek.',
      data.excluded_articles or 0, data.unclassified_articles or 0))
  end
  if (data.unreadable_articles or 0) > 0 or (data.unavailable_photos or 0) > 0 then
    table.insert(lines, string.format('Niet leesbaar: %d artikelen; niet selecteerbaar: %d foto’s (metadata/voorbeeld ontbreekt).',
      data.unreadable_articles or 0, data.unavailable_photos or 0))
  end
  s.next_offset = data.next_offset
  if type(s.next_offset) == 'number' then table.insert(lines, 'Meer resultaten beschikbaar: ]p.') end
  vim.bo[s.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(s.buffer, 0, -1, false, lines)
  vim.bo[s.buffer].modifiable = false
end

search = function(s, query, offset)
  if s.busy then return end
  stop_browser(s)
  s.query = query
  notify('Pubble-foto’s zoeken…', vim.log.levels.INFO)
  run(s, { 'search', '--query', query, '--offset', tostring(offset) }, nil, function(data) render(s, data) end)
end

function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  buf = vim.b[buf].pubble_photo_source or buf
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    notify('Open een bewerkbaar artikel om een foto te kiezen.', vim.log.levels.WARN)
    return
  end
  if vim.b[buf].publication_in_progress == true then
    notify('Wacht tot de huidige verzending klaar is.', vim.log.levels.WARN)
    return
  end
  local existing = sessions[buf]
  if existing and current(existing) and existing.input_win and vim.api.nvim_win_is_valid(existing.input_win) then
    vim.api.nvim_set_current_win(existing.input_win)
    return
  end
  if existing then close(existing) end
  local source_win = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  local s = { source = buf, source_win = source_win, tick = vim.api.nvim_buf_get_changedtick(buf) }
  sessions[buf] = s
  run(s, { 'suggest' }, text(buf), function(data) ask_query(s, data.query) end)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('PubblePhotoBrowserCleanup', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = function()
    for _, s in pairs(sessions) do stop_browser(s) end
  end })
  vim.api.nvim_create_user_command('PubbleFoto', function() M.open() end, { desc = 'Bestaande Pubble-foto zoeken en kiezen' })
  vim.keymap.set('n', '<leader>pf', function() M.open() end, { desc = '[P]ubble: [F]oto zoeken en kiezen' })
end

M._current = current
return M
