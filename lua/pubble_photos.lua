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

local function dispose(s)
  s.closed = true
  if sessions[s.source] == s then sessions[s.source] = nil end
  if s.busy and s.process and type(s.process.kill) == 'function' then
    pcall(s.process.kill, s.process, 15)
  end
  if s.gallery then vim.fn.delete(s.gallery) end
end

local function close(s)
  dispose(s)
  if s.buffer and vim.api.nvim_buf_is_valid(s.buffer) then
    vim.api.nvim_buf_delete(s.buffer, { force = true })
  end
end

local function selected(s)
  if not s.buffer or not vim.api.nvim_buf_is_valid(s.buffer) then return end
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return s.rows[line]
end

local function choose(s)
  local photo = selected(s)
  if not photo or s.busy then return end
  if not current(s) then
    notify('Artikel is gewijzigd. Open de fotokeuze opnieuw.', vim.log.levels.WARN)
    return
  end
  local credit = photo.credit ~= '' and photo.credit or '(leeg — aanvullen in c:)'
  local caption = photo.caption ~= '' and photo.caption or '(leeg — aanvullen in b:)'
  if dialog.confirm('Deze foto gebruiken? Controleer context en gebruiksrechten.\n\n'
      .. photo.source_title .. '\nCredit: ' .. credit .. '\nBijschrift: ' .. caption,
      '&Ja\n&Nee', 2) ~= 1 then return end
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

local search
local function ask_query(s, initial)
  dialog.input({ prompt = 'Pubble-foto’s zoeken (alle kranten): ', default = initial or s.query or '' }, function(query)
    if query and vim.trim(query) ~= '' and current(s) then search(s, query, 0) end
  end)
end

local function render(s, data)
  if not s.buffer or not vim.api.nvim_buf_is_valid(s.buffer) then
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
    map('g', function()
      if s.gallery then browser.open_urls({ s.gallery }) end
    end, 'Alle voorbeelden in browser bekijken')
    map('/', function() ask_query(s) end, 'Andere zoekwoorden')
    map('n', function()
      if type(s.next_offset) == 'number' then search(s, s.query, s.next_offset) end
    end, 'Volgende resultaten')
    map('q', function() close(s) end, 'Terug zonder fotokeuze')
  end
  s.rows = {}
  local lines = { 'Pubble-foto’s · ' .. s.query,
    'o: bekijk foto | g: alle voorbeelden | Enter: kies | /: zoek | n: volgende | q: terug',
    'Kies alleen beeld waarvan context en gebruiksrechten passen bij dit artikel.', '' }
  for i, photo in ipairs(data.photos or {}) do
    local first = #lines + 1
    vim.list_extend(lines, {
      string.format('%d. %s [%s · %s]', i, one_line(photo.source_title), one_line(photo.edition), one_line(photo.date)),
      '   Bijschrift: ' .. (photo.caption ~= '' and one_line(photo.caption) or '(leeg)'),
      '   Credit: ' .. (photo.credit ~= '' and one_line(photo.credit) or '(leeg)'), '',
    })
    for row = first, #lines do s.rows[row] = photo end
  end
  if #(data.photos or {}) == 0 then table.insert(lines, 'Geen selecteerbare foto’s op deze pagina. Probeer / of n.') end
  if (data.unreadable_articles or 0) > 0 or (data.unavailable_photos or 0) > 0 then
    table.insert(lines, string.format('Niet leesbaar: %d artikelen; niet selecteerbaar: %d foto’s (metadata/voorbeeld ontbreekt).',
      data.unreadable_articles or 0, data.unavailable_photos or 0))
  end
  s.next_offset = data.next_offset
  if type(s.next_offset) == 'number' then table.insert(lines, 'Meer resultaten beschikbaar: n.') end
  vim.bo[s.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(s.buffer, 0, -1, false, lines)
  vim.bo[s.buffer].modifiable = false
  if s.gallery then vim.fn.delete(s.gallery) end
  s.gallery = vim.fn.tempname() .. '.html'
  vim.fn.writefile(vim.split(data.gallery_html or '', '\n', { plain = true }), s.gallery)
end

search = function(s, query, offset)
  if s.busy then return end
  s.query = query
  notify('Pubble-foto’s zoeken…', vim.log.levels.INFO)
  run(s, { 'search', '--query', query, '--offset', tostring(offset) }, nil, function(data) render(s, data) end)
end

function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
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
  if sessions[buf] then close(sessions[buf]) end
  local s = { source = buf, tick = vim.api.nvim_buf_get_changedtick(buf) }
  sessions[buf] = s
  run(s, { 'suggest' }, text(buf), function(data) ask_query(s, data.query) end)
end

function M.setup()
  vim.api.nvim_create_user_command('PubbleFoto', function() M.open() end, { desc = 'Bestaande Pubble-foto zoeken en kiezen' })
  vim.keymap.set('n', '<leader>pf', function() M.open() end, { desc = '[P]ubble: [F]oto zoeken en kiezen' })
end

M._current = current
return M
