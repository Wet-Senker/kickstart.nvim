-- Dunne NeoVim-client voor de archiefzoeker.
--
-- <leader>aa op een artikelbuffer haalt vijf eerder verschenen verhalen over
-- hetzelfde onderwerp op; nogmaals drukken geeft de volgende vijf. In de
-- keuzebuffer vat <leader>as samen wat je hebt laten staan.
--
-- Alle logica zit in texttools.archive_context; dit bestand kent alleen de
-- buffer, de sneltoets en de melding.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local context_help = require 'context_help'

local command = commands.bin 'archive-context'
local PAGE_SIZE = 5

local function workflow(message, level, options)
  notifications.workflow(message, level, options)
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

--- Schrijf de buffer naar een tijdelijk bestand; de CLI werkt op bestanden.
local function write_temp(buf)
  local file = vim.fn.tempname() .. '.md'
  if vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), file) ~= 0 then
    return nil
  end
  return file
end

local function decode(result, fallback)
  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    vim.notify(message ~= '' and message or fallback, vim.log.levels.ERROR)
    return nil
  end
  local ok, data = pcall(vim.json.decode, vim.trim(result.stdout or ''))
  if not ok or type(data) ~= 'table' then
    vim.notify('Onleesbaar antwoord van de archiefzoeker.', vim.log.levels.ERROR)
    return nil
  end
  return data
end

--- Hoort de bewaarde positie nog bij deze tekst?
--
-- Net als bij de doublurecontrole hangt de lijst aan de artikeltekst. Wordt het
-- artikel herschreven, dan zijn de ankerwoorden anders en begint het bladeren
-- opnieuw bij de bovenste vijf.
local function offset_for(buf)
  local text = buffer_text(buf)
  if vim.b[buf].archive_context_body ~= text then
    return 0
  end
  local offset = vim.b[buf].archive_context_offset
  return type(offset) == 'number' and offset or 0
end

local function selection_count(text)
  local block = text:match('<!%-%- selection%-start %-%->(.-)<!%-%- selection%-end %-%->')
  if not block then return 0 end
  local count = 0
  for line in block:gmatch '[^\n]+' do
    if line:match '^%s*%d+%.%s+%S' then count = count + 1 end
  end
  return count
end

local function help_entry(buf)
  local text = buffer_text(buf)
  local chosen = selection_count(text)
  local entry = { title = 'Archiefzoeker', sections = {} }
  if chosen == 0 then
    entry.status = 'Geen artikelen meer geselecteerd.'
    table.insert(entry.sections, {
      heading = 'Nu doen',
      lines = { 'Laat minimaal één genummerde regel staan, of sluit deze buffer.' },
    })
  else
    entry.status = string.format('%d eerder artikel(en) geselecteerd.', chosen)
    table.insert(entry.sections, {
      heading = 'Nu doen',
      lines = {
        '<leader>as  Vat deze artikelen samen tot één ## Achtergrond in je artikel.',
        'Verwijder met dd wat je niet wilt meenemen.',
      },
    })
  end
  table.insert(entry.sections, {
    heading = 'Andere opties',
    lines = {
      string.format('<leader>aa  Haal de volgende %d verhalen op.', PAGE_SIZE),
      'De lijst staat op relevantie; binnen de pagina is hij per jaar gegroepeerd.',
      'De achtergrondtekst blijft zichtbaar in je artikel en gaat vóór verzending weg.',
    },
  })
  return entry
end

local function open_review(source_buf, document, offset)
  local existing = vim.b[source_buf].archive_context_review_buf
  local buf = existing
  local lines = vim.split(document, '\n', { plain = true })
  if lines[#lines] == '' then table.remove(lines) end

  if not (type(buf) == 'number' and vim.api.nvim_buf_is_valid(buf)) then
    buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = 'markdown'
    vim.bo[buf].bufhidden = 'hide'
    pcall(vim.api.nvim_buf_set_name, buf, 'Archief · eerder geschreven')
    vim.cmd 'botright vsplit'
    vim.api.nvim_win_set_buf(0, buf)
    vim.b[buf].archive_context_review = true
    vim.b[buf].archive_context_source = source_buf
    context_help.register(buf, function(target) return help_entry(target) end)
    vim.keymap.set('n', '<leader>as', function() M.summarise(buf) end, {
      buffer = buf,
      desc = '[A]rchief [s]amenvatten tot achtergrond',
    })
    vim.keymap.set('n', '<leader>aa', function() M.search(source_buf) end, {
      buffer = buf,
      desc = '[A]rchief: volgende vijf verhalen',
    })
  else
    -- Dezelfde buffer hergebruiken houdt de vensterindeling rustig bij bladeren.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[source_buf].archive_context_review_buf = buf
  vim.b[buf].archive_context_offset = offset
  return buf
end

function M.search(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf].archive_context_review == true then
    local source = vim.b[buf].archive_context_source
    if type(source) == 'number' and vim.api.nvim_buf_is_valid(source) then
      return M.search(source)
    end
    vim.notify('De bijbehorende artikelbuffer bestaat niet meer.', vim.log.levels.WARN)
    return
  end
  if vim.b[buf].archive_context_running == true then
    workflow('De archiefzoeker loopt al.', vim.log.levels.INFO)
    return
  end

  local text = buffer_text(buf)
  local offset = offset_for(buf)
  local file = write_temp(buf)
  if not file then
    vim.notify('Kon het artikel niet tijdelijk wegschrijven.', vim.log.levels.ERROR)
    return
  end

  vim.b[buf].archive_context_running = true
  workflow(
    offset == 0 and 'Archief · eerdere berichten zoeken…'
      or string.format('Archief · verhalen %d en verder ophalen…', offset + 1),
    vim.log.levels.INFO
  )
  vim.system(
    { command, file, '--offset', tostring(offset), '--json' },
    { text = true },
    function(result)
      vim.schedule(function()
        vim.fn.delete(file)
        if vim.api.nvim_buf_is_valid(buf) then
          vim.b[buf].archive_context_running = false
        end
        local data = decode(result, 'Archiefzoeker mislukt.')
        if not data or not vim.api.nvim_buf_is_valid(buf) then return end
        local shown = type(data.shown) == 'table' and #data.shown or 0
        local total = type(data.articles) == 'table' and #data.articles or 0
        if shown == 0 then
          workflow(
            offset == 0 and 'Er is niet eerder over dit onderwerp geschreven.'
              or 'Er zijn geen verdere verhalen meer.',
            vim.log.levels.INFO,
            { ttl = 8 }
          )
          return
        end
        open_review(buf, data.review, offset)
        vim.b[buf].archive_context_body = text
        vim.b[buf].archive_context_offset = offset + shown
        workflow(
          string.format(
            '%d van %d verhalen getoond. Laat staan wat je wilt en druk <leader>as; <leader>aa geeft de volgende %d.',
            offset + shown, total, PAGE_SIZE
          ),
          vim.log.levels.INFO,
          { ttl = 12 }
        )
      end)
    end
  )
end

function M.summarise(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf].archive_context_review ~= true then
    vim.notify('Open eerst een archieflijst met <leader>aa.', vim.log.levels.WARN)
    return
  end
  local source = vim.b[buf].archive_context_source
  if not (type(source) == 'number' and vim.api.nvim_buf_is_valid(source)) then
    vim.notify('De bijbehorende artikelbuffer bestaat niet meer.', vim.log.levels.WARN)
    return
  end
  if selection_count(buffer_text(buf)) == 0 then
    vim.notify('Laat minimaal één regel staan om samen te vatten.', vim.log.levels.WARN)
    return
  end

  local review_file = vim.fn.tempname() .. '.md'
  if vim.fn.writefile(vim.api.nvim_buf_get_lines(buf, 0, -1, false), review_file) ~= 0 then
    vim.notify('Kon de keuzelijst niet tijdelijk wegschrijven.', vim.log.levels.ERROR)
    return
  end
  local article_file = write_temp(source)
  if not article_file then
    vim.fn.delete(review_file)
    vim.notify('Kon het artikel niet tijdelijk wegschrijven.', vim.log.levels.ERROR)
    return
  end

  workflow('Archief · achtergrondtekst schrijven…', vim.log.levels.INFO)
  vim.system(
    { command, article_file, '--summarise', review_file, '--json' },
    { text = true },
    function(result)
      vim.schedule(function()
        vim.fn.delete(review_file)
        vim.fn.delete(article_file)
        local data = decode(result, 'Achtergrondtekst maken mislukt.')
        if not data or type(data.background) ~= 'string' then return end
        if not vim.api.nvim_buf_is_valid(source) then
          vim.notify('De artikelbuffer is intussen gesloten.', vim.log.levels.WARN)
          return
        end
        M.apply(source, data.background)
        workflow(
          'Achtergrond toegevoegd onder ## Achtergrond. Lees hem na; hij gaat vóór verzending weer weg.',
          vim.log.levels.INFO,
          { ttl = 12 }
        )
      end)
    end
  )
end

--- Zet de achtergrondtekst als zichtbare sectie onderaan het artikel.
--
-- Bewust een gewone sectie en niet de herschrijfprompt in: een model dat een
-- oud artikel naast een nieuw krijgt, mengt stil feiten uit beide.
function M.apply(buf, background)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local start_index = nil
  for index, line in ipairs(lines) do
    if line:match '^##%s+Achtergrond%s*$' then
      start_index = index
      break
    end
  end
  if start_index then
    -- Een eerdere achtergrond vervangen, inclusief de scheidingsregel erboven.
    local stop_index = #lines
    for index = start_index + 1, #lines do
      if lines[index]:match '^##%s' then
        stop_index = index - 1
        break
      end
    end
    local first = start_index
    while first > 1 and vim.trim(lines[first - 1]) == '' do first = first - 1 end
    if first > 1 and vim.trim(lines[first - 1]) == '---' then first = first - 1 end
    vim.api.nvim_buf_set_lines(buf, first - 1, stop_index, false, {})
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  while #lines > 0 and vim.trim(lines[#lines]) == '' do table.remove(lines) end
  local addition = { '', '---', '', '## Achtergrond', '' }
  vim.list_extend(addition, vim.split(vim.trim(background), '\n', { plain = true }))
  vim.api.nvim_buf_set_lines(buf, #lines, -1, false, addition)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('Archief', function() M.search() end, {
    desc = 'Eerder geschreven artikelen over dit onderwerp zoeken',
  })
  vim.keymap.set('n', '<leader>aa', function() M.search() end, {
    desc = '[A]rchief: eerder geschreven over dit onderwerp',
  })
end

M._selection_count = selection_count
M._help_entry = help_entry
M._offset_for = offset_for

return M
