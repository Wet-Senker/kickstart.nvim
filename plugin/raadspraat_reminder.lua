local M = {}

local python = vim.fn.expand('~/workspace/texttools/.venv/bin/python')
local module = 'texttools.raadspraat_reminder_cli'
local mail_script = vim.fn.expand('~/workspace/texttools/nvim/raadspraat_mail.applescript')

local function dutch_short_date(iso_date)
  local year, month, day = iso_date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  return string.format('%s-%s-%s', day, month, year)
end

local function is_sent(item)
  return type(item.sent_at) == 'string' and item.sent_at ~= ''
end

-- Het fractie-overzicht opent in dezelfde mailbuffer als een reminder, maar
-- hoort geen verzendstatus te krijgen: er valt niets af te vinken.
local function markable(item)
  return type(item.id) == 'string' and item.id ~= ''
end

local function run(args)
  local output = vim.fn.system(vim.list_extend({ python, '-m', module }, args))
  if vim.v.shell_error ~= 0 then
    vim.notify(vim.trim(output), vim.log.levels.ERROR)
    return nil
  end
  return output
end

local function reload_menu()
  vim.schedule(function() M.reminders() end)
end

local function mark(item, sent)
  if not markable(item) then return end
  local result = run({ sent and 'sent' or 'unsent', item.id })
  if not result then return end
  vim.notify(sent and 'Reminder gemarkeerd als verstuurd.' or 'Verzendmarkering verwijderd.')
  reload_menu()
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
  local group = vim.api.nvim_create_augroup('RaadspraatMailReturn', { clear = true })
  vim.api.nvim_create_autocmd('FocusGained', {
    group = group,
    once = true,
    callback = function()
      vim.defer_fn(function()
        vim.ui.select({ 'Ja', 'Nee' }, {
          prompt = 'Reminder voor ' .. item.party .. ' verstuurd?',
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
    'osascript',
    mail_script,
    message.recipient,
    message.subject,
    message.body,
  })
  if vim.v.shell_error ~= 0 then
    vim.notify(
      'Apple Mail kon niet worden geopend: ' .. vim.trim(output),
      vim.log.levels.ERROR
    )
    return
  end

  if markable(item) then confirm_sent_on_return(item) end
  vim.notify('Concept voor ' .. item.party .. ' geopend in Apple Mail.')
end

local function copy_mail(item, buf)
  local message, error_message = mail_from_buffer(buf)
  if not message then
    vim.notify(error_message, vim.log.levels.ERROR)
    return
  end
  local mail = table.concat({
    'Aan: ' .. message.recipient,
    'Onderwerp: ' .. message.subject,
    '',
    message.body,
    '',
  }, '\n')
  vim.fn.setreg('+', mail)
  vim.notify('Tekst voor ' .. item.party .. ' staat op het klembord.')

  if not markable(item) then return end
  vim.ui.select({ 'Ja', 'Nee' }, {
    prompt = 'Nu markeren als verstuurd?',
  }, function(choice)
    if choice == 'Ja' then mark(item, true) end
  end)
end

-- ? in de reminderbuffer — zelfde vorm als de texttools-cheatsheet.
local function show_help()
  local lines = {
    ' Raadspraat',
    '',
    ' <leader>aw   concept openen in Apple Mail',
    ' c            tekst naar het klembord',
    ' s            verzendstatus wisselen (○ / ✓) — alleen bij een reminder',
    ' ?            deze hulp',
    ' q            sluiten',
    '',
    ' In het menu (<leader>kr):',
    ' Reminders                 de rotatie; ▶ = deze week de deur uit',
    '                           ○ nog niet verstuurd   ✓ verstuurd',
    ' Overzicht                 planning voor één fractie of voor allemaal',
    ' Artikel maken             foto + template kiezen',
    '',
    ' De tekst hierboven is bewerkbaar; wat je wijzigt gaat mee',
    ' naar Apple Mail of het klembord.',
  }

  local width = 62
  local height = #lines
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
  vim.cmd('new')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'mail'
  vim.api.nvim_buf_set_name(buf, 'Raadspraat – ' .. item.party)

  local lines = {
    'Aan: ' .. item.email,
    'Onderwerp: ' .. item.subject,
    '',
  }
  vim.list_extend(lines, vim.split(item.body, '\n', { plain = true }))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false

  vim.keymap.set('n', 'c', function() copy_mail(item, buf) end, {
    buffer = buf,
    silent = true,
    desc = 'Kopieer reminder en registreer verzending',
  })
  vim.keymap.set('n', '<leader>aw', function() open_in_mail(item, buf) end, {
    buffer = buf,
    silent = true,
    desc = 'Open Raadspraat-concept in Apple Mail',
  })
  if markable(item) then
    vim.keymap.set('n', 's', function() mark(item, not is_sent(item)) end, {
      buffer = buf,
      silent = true,
      desc = 'Wissel verzendstatus',
    })
  end
  vim.keymap.set('n', 'q', '<cmd>close<cr>', {
    buffer = buf,
    silent = true,
    desc = 'Sluit reminder',
  })
  vim.keymap.set('n', '?', show_help, {
    buffer = buf,
    silent = true,
    desc = 'Toon toetsen',
  })

  local hint = '<leader>aw = Apple Mail  •  c = kopiëren  •  ? = hulp  •  q = sluiten'
  if markable(item) then
    hint = '<leader>aw = Apple Mail  •  c = kopiëren  •  s = status  •  ? = hulp  •  q = sluiten'
  end
  vim.notify(hint)
end

local function fetch_rotation()
  local output = run({ 'list', '--json' })
  if not output then return nil end
  local ok, items = pcall(vim.json.decode, output)
  if not ok or type(items) ~= 'table' then
    vim.notify('De Raadspraat-planning kon niet worden gelezen.', vim.log.levels.ERROR)
    return nil
  end
  return items
end

-- `items` mag vooraf opgehaald zijn (M.menu doet dat al voor zijn label),
-- zodat één keer <leader>kr niet twee keer Python start.
function M.reminders(items)
  items = items or fetch_rotation()
  if not items then return end

  vim.ui.select(items, {
    prompt = 'Raadspraat-reminder:',
    format_item = function(item)
      local status = is_sent(item) and '✓' or '○'
      -- ▶ = de reminder van deze week; die hoor je nu te versturen.
      local marker = item.is_current and '▶' or ' '
      return string.format(
        '%s %s %-22s  aanleveren W%02d %s  →  plaatsing W%02d %s',
        marker,
        status,
        item.party,
        item.deadline_week,
        dutch_short_date(item.deadline),
        item.publication_week,
        dutch_short_date(item.publication_date)
      )
    end,
  }, function(item)
    if item then open_preview(item) end
  end)
end

-- Het overzicht is óók gewoon een mail, dus het opent in dezelfde buffer:
-- c kopieert en <leader>aw maakt er een concept van, net als bij een reminder.
function M.overview(items)
  items = items or fetch_rotation()
  if not items then return end

  local choices = { { label = 'Alle fracties tegelijk' } }
  for _, item in ipairs(items) do
    table.insert(choices, { label = item.party, party = item.party })
  end

  vim.ui.select(choices, {
    prompt = 'Overzicht sturen aan:',
    format_item = function(choice) return choice.label end,
  }, function(choice)
    if not choice then return end

    local args = { 'overzicht', '--json' }
    if choice.party then table.insert(args, 2, choice.party) end
    local output = run(args)
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
      party = choice.party or 'alle fracties',
      email = table.concat(mail.recipients or {}, ', '),
      subject = mail.subject,
      body = mail.body,
    })
  end)
end

function M.menu()
  local items = fetch_rotation()
  if not items then return end

  local huidig
  for _, item in ipairs(items) do
    if item.is_current then huidig = item.party end
  end

  local entries = {
    {
      label = huidig and ('Reminders  (▶ ' .. huidig .. ' deze week)') or 'Reminders',
      action = function() M.reminders(items) end,
    },
    {
      label = 'Overzicht voor de fracties',
      action = function() M.overview(items) end,
    },
    {
      label = 'Artikel maken (foto + template)',
      action = function() require('krant').raadspraat_menu() end,
    },
  }

  vim.ui.select(entries, {
    prompt = 'Raadspraat:',
    format_item = function(entry) return entry.label end,
  }, function(entry)
    if entry then entry.action() end
  end)
end

vim.keymap.set('n', '<leader>kr', M.menu, {
  desc = '[K]rant [R]aadspraat',
})

return M
