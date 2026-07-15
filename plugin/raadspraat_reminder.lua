local M = {}

local python = vim.fn.expand('~/workspace/texttools/.venv/bin/python')
local module = 'texttools.raadspraat_reminder_cli'
local mail_script = vim.fn.expand('~/workspace/texttools/nvim/raadspraat_mail.applescript')

local function dutch_short_date(iso_date)
  local year, month, day = iso_date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
  return string.format('%s-%s-%s', day, month, year)
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
  vim.schedule(function() M.menu() end)
end

local function mark(item, sent)
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

  confirm_sent_on_return(item)
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
  vim.notify('Reminder voor ' .. item.party .. ' staat op het klembord.')

  vim.ui.select({ 'Ja', 'Nee' }, {
    prompt = 'Nu markeren als verstuurd?',
  }, function(choice)
    if choice == 'Ja' then mark(item, true) end
  end)
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
  vim.keymap.set('n', 's', function() mark(item, not item.sent_at) end, {
    buffer = buf,
    silent = true,
    desc = 'Wissel verzendstatus',
  })
  vim.keymap.set('n', 'q', '<cmd>close<cr>', {
    buffer = buf,
    silent = true,
    desc = 'Sluit reminder',
  })
  vim.notify('<leader>aw = Apple Mail  •  c = kopiëren  •  s = status  •  q = sluiten')
end

function M.menu()
  local output = run({ 'list', '--json' })
  if not output then return end
  local ok, items = pcall(vim.json.decode, output)
  if not ok then
    vim.notify('De Raadspraat-planning kon niet worden gelezen.', vim.log.levels.ERROR)
    return
  end

  vim.ui.select(items, {
    prompt = 'Raadspraat-reminder:',
    format_item = function(item)
      local status = item.sent_at and '✓' or '○'
      return string.format(
        '%s %-22s  aanleveren W%02d %s  →  plaatsing W%02d %s',
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

vim.keymap.set('n', '<leader>kr', M.menu, {
  desc = '[K]rant [R]aadspraat-reminders',
})

return M
