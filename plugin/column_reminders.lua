-- Reminders voor de vaste rubrieken met een beurtrotatie.
--
--   <leader>kp  planning voor Raadspraat en Ondernemen in Kampen
--
-- Beide rubrieken gebruiken dezelfde reminder- en overzichtslogica. Artikel
-- maken hoort bij de templates en loopt daarom via <leader>kt.

local M = {}

local texttools_commands = require('texttools_commands')
local notifications = require('texttools_notify')
local mail_script = texttools_commands.path('nvim', 'raadspraat_mail.applescript')

local RUBRIEKEN = {
  raadspraat = {
    naam = 'Raadspraat',
  },
  ondernemen = {
    naam = 'Ondernemen in Kampen',
  },
}

local RUBRIEK_VOLGORDE = { 'raadspraat', 'ondernemen' }

local function is_sent(item)
  return type(item.sent_at) == 'string' and item.sent_at ~= ''
end

-- Een overzicht opent in dezelfde mailbuffer als een reminder, maar hoort geen
-- verzendstatus te krijgen: er valt niets af te vinken.
local function markable(item)
  return type(item.id) == 'string' and item.id ~= ''
end

local function run(series, args)
  local output = vim.fn.system(vim.list_extend({ texttools_commands.bin(series .. '-reminder') }, args))
  if vim.v.shell_error ~= 0 then
    vim.notify(vim.trim(output), vim.log.levels.ERROR)
    return nil
  end
  return output
end

local function reload_menu(series)
  vim.schedule(function() M.reminders(series) end)
end

local function mark(item, sent)
  if not markable(item) then return end
  local result = run(item.series, { sent and 'sent' or 'unsent', item.id })
  if not result then return end
  notifications.workflow(
    sent and 'Reminder gemarkeerd als verstuurd.' or 'Verzendmarkering verwijderd.',
    nil,
    { annote = 'Planning' }
  )
  reload_menu(item.series)
end

local function mail_from_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local recipient = (lines[1] or ''):match('^Aan:%s*(.-)%s*$')
  local subject = (lines[2] or ''):match('^Onderwerp:%s*(.-)%s*$')
  local body_lines = {}
  for index = 4, #lines do table.insert(body_lines, lines[index]) end
  local body = table.concat(body_lines, '\n'):gsub('%s+$', '')

  if not recipient or recipient == '' then return nil, 'Een geldig veld Aan: ontbreekt.' end
  if not subject or subject == '' then return nil, 'Een geldig veld Onderwerp: ontbreekt.' end
  if body == '' then return nil, 'De berichttekst is leeg.' end
  return { recipient = recipient, subject = subject, body = body }
end

local function confirm_sent_on_return(item)
  local group = vim.api.nvim_create_augroup('ColumnMailReturn', { clear = true })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    once = true,
    callback = function()
      vim.defer_fn(function()
        vim.ui.select({ 'Ja', 'Nee' }, {
          prompt = 'Reminder voor ' .. item.label .. ' verstuurd?',
        }, function(choice)
          if choice == 'Ja' then mark(item, true) end
        end)
      end, 150)
    end,
  })
end

local function open_in_mail(item, buf)
  local message, error_message = mail_from_buffer(buf)
  if not message then
    vim.notify(error_message, vim.log.levels.ERROR)
    return
  end

  local output = vim.fn.system({
    'osascript', mail_script, message.recipient, message.subject, message.body,
  })
  if vim.v.shell_error ~= 0 then
    vim.notify('Apple Mail kon niet worden geopend: ' .. vim.trim(output), vim.log.levels.ERROR)
    return
  end

  if markable(item) then confirm_sent_on_return(item) end
  notifications.workflow(
    'Concept voor ' .. item.label .. ' geopend in Apple Mail.',
    nil,
    { annote = 'Planning' }
  )
end

local function copy_mail(item, buf)
  local message, error_message = mail_from_buffer(buf)
  if not message then
    vim.notify(error_message, vim.log.levels.ERROR)
    return
  end

  vim.fn.setreg('+', table.concat({
    'Aan: ' .. message.recipient,
    'Onderwerp: ' .. message.subject,
    '',
    message.body,
    '',
  }, '\n'))
  local soort = markable(item) and ('Reminder voor ' .. item.label) or 'Planningsmail'
  notifications.workflow(
    soort .. ' staat volledig op het klembord. De verzendstatus is niet gewijzigd.',
    nil,
    { annote = 'Planning', ttl = 10 }
  )
end

-- ? in de mailbuffer — zelfde vorm als de texttools-cheatsheet.
local function show_help()
  local lines = {
    ' Rubriekreminders',
    '',
    ' <leader>aw   concept openen in Apple Mail',
    ' c            volledige mail kopiëren; status blijft gelijk',
    ' s            status handmatig corrigeren (○ / ✓) — alleen reminder',
    ' ?            deze hulp',
    ' q            sluiten',
    '',
    ' Het menu:    <leader>kp = rubriekplanning',
    ' Reminders                 de rotatie; ▶ = deze week de deur uit',
    '                           ○ nog niet verstuurd   ✓ verstuurd',
    ' Planningsoverzicht        voor één deelnemer of voor allemaal',
    ' Artikel maken             via <leader>kt (rubriektemplates)',
    '',
    ' De tekst hierboven is bewerkbaar; wat je wijzigt gaat mee',
    ' naar Apple Mail of het klembord.',
  }

  local width, height = 66, #lines
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = ' Toetsen ',
    title_pos = 'center',
  })
  vim.wo[win].wrap = false

  for _, key in ipairs({ 'q', '<Esc>', '?' }) do
    vim.keymap.set('n', key, '<cmd>close<cr>', { buffer = buf, silent = true })
  end
end

local function open_preview(item)
  local rubriek = RUBRIEKEN[item.series] or { naam = item.series }
  vim.cmd('new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mail'
  vim.api.nvim_buf_set_name(buf, rubriek.naam .. ' – ' .. item.label)

  local lines = { 'Aan: ' .. item.email, 'Onderwerp: ' .. item.subject, '' }
  vim.list_extend(lines, vim.split(item.body, '\n', { plain = true }))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  vim.keymap.set('n', 'c', function() copy_mail(item, buf) end,
    { buffer = buf, silent = true, desc = 'Kopieer volledige mail' })
  vim.keymap.set('n', '<leader>aw', function() open_in_mail(item, buf) end,
    { buffer = buf, silent = true, desc = 'Open concept in Apple Mail' })
  if markable(item) then
    vim.keymap.set('n', 's', function() mark(item, not is_sent(item)) end,
      { buffer = buf, silent = true, desc = 'Corrigeer verzendstatus handmatig' })
  end
  vim.keymap.set('n', 'q', '<cmd>close<cr>',
    { buffer = buf, silent = true, desc = 'Sluiten' })
  vim.keymap.set('n', '?', show_help,
    { buffer = buf, silent = true, desc = 'Toon toetsen' })

  local hint = '<leader>aw = Apple Mail  •  c = volledige mail kopiëren  •  ? = hulp  •  q = sluiten'
  if markable(item) then
    hint = '<leader>aw = Apple Mail  •  c = volledige mail kopiëren  •  s = status corrigeren  •  ? = hulp  •  q = sluiten'
  end
  notifications.workflow(hint, nil, { annote = 'Planning', ttl = 12 })
end

local function fetch_rotation(series)
  local output = run(series, { 'list', '--json' })
  if not output then return nil end
  local ok, items = pcall(vim.json.decode, output)
  if not ok or type(items) ~= 'table' then
    vim.notify('De planning kon niet worden gelezen.', vim.log.levels.ERROR)
    return nil
  end
  return items
end

-- `items` mag vooraf opgehaald zijn, zodat terugnavigeren niet opnieuw Python
-- hoeft te starten.
function M.reminders(series, items)
  items = items or fetch_rotation(series)
  if not items then return end

  local choices = {}
  for _, item in ipairs(items) do table.insert(choices, item) end
  table.insert(choices, {
    _back = true,
    label = '← Terug naar ' .. ((RUBRIEKEN[series] or {}).naam or 'rubriekmenu'),
  })

  local breedte = 0
  for _, item in ipairs(items) do breedte = math.max(breedte, #item.label) end

  vim.ui.select(choices, {
    prompt = (RUBRIEKEN[series] or {}).naam or 'Reminder',
    format_item = function(item)
      if item._back then return item.label end
      local status = is_sent(item) and '✓' or '○'
      -- ▶ = de reminder van deze week; die hoor je nu te versturen.
      local marker = item.is_current and '▶' or ' '
      return string.format(
        '%s %s %-' .. breedte .. 's  Reminder W%02d - aanleveren W%02d - pub W%02d',
        marker, status, item.label,
        item.reminder_week,
        item.deadline_week,
        item.publication_week
      )
    end,
  }, function(item)
    if not item then return end
    if item._back then
      vim.schedule(function() M.series_menu(series, items) end)
    else
      open_preview(item)
    end
  end)
end

-- Het overzicht is óók gewoon een mail, dus het opent in dezelfde buffer.
function M.overview(series, items)
  items = items or fetch_rotation(series)
  if not items then return end

  local choices = {
    { label = 'Gezamenlijke planning voor alle deelnemers' },
  }
  for _, item in ipairs(items) do
    table.insert(choices, { label = item.label, wie = item.label })
  end
  table.insert(choices, {
    _back = true,
    label = '← Terug naar ' .. ((RUBRIEKEN[series] or {}).naam or 'rubriekmenu'),
  })

  vim.ui.select(choices, {
    prompt = 'Planningsoverzicht voor:',
    format_item = function(choice) return choice.label end,
  }, function(choice)
    if not choice then return end
    if choice._back then
      vim.schedule(function() M.series_menu(series, items) end)
      return
    end

    local args = { 'overzicht', '--json' }
    if choice.wie then table.insert(args, 2, choice.wie) end
    local output = run(series, args)
    if not output then return end

    local ok, mail = pcall(vim.json.decode, output)
    if not ok or type(mail) ~= 'table' or type(mail.body) ~= 'string' then
      vim.notify('Het overzicht kon niet worden gelezen.', vim.log.levels.ERROR)
      return
    end

    -- Waarschuwing bóven de tekst, niet erin: de mail moet schoon blijven.
    for _, warning in ipairs(mail.warnings or {}) do
      vim.notify('LET OP — ' .. warning, vim.log.levels.WARN)
    end

    open_preview({
      series = series,
      label = choice.wie or 'iedereen',
      email = table.concat(mail.recipients or {}, ', '),
      subject = mail.subject,
      body = mail.body,
    })
  end)
end

function M.series_menu(series, items)
  local rubriek = RUBRIEKEN[series]
  items = items or fetch_rotation(series)
  if not items then return end

  local entries = {
    {
      label = 'Reminders',
      action = function() M.reminders(series, items) end,
    },
    {
      label = 'Planningsoverzicht',
      action = function() M.overview(series, items) end,
    },
    {
      label = '← Terug naar rubriekplanning',
      action = function() M.menu() end,
    },
  }

  vim.ui.select(entries, {
    prompt = rubriek.naam .. ':',
    format_item = function(entry) return entry.label end,
  }, function(entry)
    if entry then entry.action() end
  end)
end

function M.menu()
  local entries = {}
  for _, series in ipairs(RUBRIEK_VOLGORDE) do
    table.insert(entries, { series = series, label = RUBRIEKEN[series].naam })
  end

  vim.ui.select(entries, {
    prompt = 'Rubriekplanning:',
    format_item = function(entry) return entry.label end,
  }, function(entry)
    if entry then M.series_menu(entry.series) end
  end)
end

vim.api.nvim_create_user_command('RubriekPlanning', M.menu, {
  desc = 'Planning en reminders voor Raadspraat en Ondernemen in Kampen',
  force = true,
})

vim.keymap.set('n', '<leader>kp', M.menu, {
  desc = '[K]rant [P]lanning rubrieken',
})

return M
