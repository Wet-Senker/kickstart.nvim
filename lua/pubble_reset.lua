-- Reset van een mislukte of onjuiste Pubble-verzending.
--
-- Alle beslissingen (wat is aangemaakt, wat gaat offline, welke herstelkopie
-- geldt) liggen in Python (`texttools.pubble_reset`). Deze module toont het
-- plan, vraagt bevestiging en zet daarna de lokale tekst terug.
local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local dialog = require 'user_dialog'
local texttools_paths = require 'texttools_paths'

local python = commands.bin 'python'
local module = 'texttools.pubble_reset'
local active = {}

-- Bufferstate van een lopende of mislukte verzending. Na een reset hoort de
-- volgende <leader>aw weer van voren af aan te beginnen.
local STATE_KEYS = {
  'publication_review_state',
  'event_review_state',
  'late_newspaper_decision',
  'skip_newspaper_editions',
  'print_timing_reentry',
}

local function workflow(message, level, options)
  notifications.workflow(message, level, options)
end

local function buffer_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

local function command(sub)
  return { python, '-m', module, sub }
end

local function decode(stdout)
  local ok, data = pcall(vim.json.decode, vim.trim(stdout or ''))
  if ok and type(data) == 'table' then return data end
  return nil
end

local function text(value)
  return type(value) == 'string' and value or nil
end

local function item_line(item)
  local label = text(item.label) or text(item.kind) or 'onderdeel'
  if type(item.object_id) == 'number' then
    label = label .. ' (' .. string.format('%d', item.object_id) .. ')'
  end
  return label
end

-- Het plan als leesbare regels, gegroepeerd op wat de reset ermee doet.
function M._summary(plan)
  local offline, manual, info = {}, {}, {}
  for _, item in ipairs(plan.items or {}) do
    if item.action == 'offline' then
      table.insert(offline, item_line(item))
    elseif item.action == 'handmatig' then
      table.insert(manual, item_line(item))
    else
      table.insert(info, item_line(item))
    end
  end

  local lines = { 'Verzending terugzetten?' }
  local function section(title, entries)
    if #entries == 0 then return end
    table.insert(lines, '')
    table.insert(lines, title)
    for _, entry in ipairs(entries) do table.insert(lines, '  • ' .. entry) end
  end
  section('Gaat offline (niet verwijderd):', offline)
  section('Blijft staan in Pubble, zelf opruimen:', manual)
  section('Kan niet worden teruggedraaid:', info)
  table.insert(lines, '')
  if text(plan.snapshot_path) and plan.snapshot_status == 'available' then
    table.insert(lines, 'Je tekst gaat terug naar vlak vóór <leader>aw.')
  else
    table.insert(lines, 'Geen herstelkopie: je tekst blijft zoals ze nu is.')
  end
  return lines
end

M._confirm = function(plan)
  return dialog.confirm(
    table.concat(M._summary(plan), '\n'),
    '&Terugzetten\n&Annuleren',
    2
  )
end

local function manual_report(plan)
  local lines = {}
  for _, item in ipairs(plan.items or {}) do
    if item.action == 'handmatig' then
      local line = '• ' .. item_line(item)
      if text(item.url) then line = line .. ' ' .. item.url end
      table.insert(lines, line)
    end
  end
  return lines
end

local function inside_inbox(path)
  local inbox = vim.fn.fnamemodify(texttools_paths.inbox(), ':p')
  return vim.startswith(vim.fn.fnamemodify(path, ':p'), inbox)
end

local function reset_buffer_state(buf)
  local failed = vim.b[buf].failed_send_file
  if type(failed) == 'string' and failed ~= ''
      and vim.fn.filereadable(failed) == 1 and inside_inbox(failed) then
    vim.fn.delete(failed)
  end
  vim.b[buf].failed_send_file = nil
  vim.b[buf].publication_in_progress = false
  for _, key in ipairs(STATE_KEYS) do vim.b[buf][key] = nil end
end

local function finish(buf)
  active[buf] = nil
end

local function apply(buf, plan, tick, source)
  vim.system(command 'apply', { text = true, stdin = source }, function(result)
    vim.schedule(function()
      finish(buf)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local outcome = decode(result.stdout)
      if not outcome then
        local err = vim.trim(result.stderr or '')
        vim.notify(
          'Reset mislukt' .. (err ~= '' and (': ' .. err) or '') .. '. Er is niets aan je tekst veranderd.',
          vim.log.levels.ERROR
        )
        return
      end

      local errors = type(outcome.errors) == 'table' and outcome.errors or {}
      if #errors > 0 then
        -- De ID's in de tekst zijn de enige verwijzing naar wat er in Pubble
        -- staat: pas terugzetten als alles offline is, anders raak je ze kwijt.
        vim.notify(
          'Niet alles kon offline worden gezet; je tekst is NIET teruggezet zodat je het opnieuw kunt proberen:\n- '
            .. table.concat(errors, '\n- '),
          vim.log.levels.ERROR
        )
        return
      end

      local restored = false
      local snapshot = text(outcome.restore_from)
      if snapshot and vim.fn.filereadable(snapshot) == 1 then
        if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
          vim.notify(
            'De tekst veranderde tijdens de reset; ze is niet overschreven. Webartikelen staan wel offline.',
            vim.log.levels.WARN
          )
        else
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn.readfile(snapshot))
          reset_buffer_state(buf)
          restored = true
        end
      end

      local lines = {
        restored
          and 'Reset klaar: webartikelen offline, tekst terug vóór <leader>aw.'
          or 'Webartikelen staan offline. De tekst is niet teruggezet.',
      }
      local manual = manual_report(plan)
      if #manual > 0 then
        table.insert(lines, 'Zelf opruimen in Pubble:')
        for _, line in ipairs(manual) do table.insert(lines, line) end
      end
      workflow(table.concat(lines, '\n'), vim.log.levels.INFO, { ttl = 20 })
    end)
  end)
end

function M.reset(target_buf)
  local buf = target_buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if active[buf] then
    workflow('Er loopt al een reset voor deze buffer.', vim.log.levels.INFO)
    return
  end
  if vim.b[buf].publication_in_progress then
    vim.notify('Er loopt nog een verzending; wacht tot die klaar is.', vim.log.levels.WARN)
    return
  end
  local source = buffer_text(buf)
  if vim.trim(source) == '' then
    vim.notify('De huidige buffer is leeg.', vim.log.levels.ERROR)
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  active[buf] = true
  vim.system(command 'plan', { text = true, stdin = source }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then
        active[buf] = nil
        return
      end
      local plan = decode(result.stdout)
      if result.code ~= 0 or not plan then
        finish(buf)
        local err = vim.trim(result.stderr or '')
        vim.notify('Resetplan maken mislukt' .. (err ~= '' and (': ' .. err) or ''), vim.log.levels.ERROR)
        return
      end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        finish(buf)
        vim.notify('De tekst veranderde tijdens het plan maken; start de reset opnieuw.', vim.log.levels.WARN)
        return
      end
      local has_items = type(plan.items) == 'table' and #plan.items > 0
      if not has_items and plan.snapshot_status ~= 'available' then
        finish(buf)
        workflow('Er is niets om terug te zetten: deze tekst is nog niet naar Pubble gestuurd.', vim.log.levels.INFO)
        return
      end
      if M._confirm(plan) ~= 1 then
        finish(buf)
        workflow('Reset geannuleerd.', vim.log.levels.INFO)
        return
      end
      apply(buf, plan, tick, source)
    end)
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('PubbleReset', function() M.reset() end, {
    desc = 'Mislukte Pubble-verzending terugzetten (webartikelen offline, tekst terug)',
  })
  vim.keymap.set('n', '<leader>aX', M.reset, {
    desc = 'Pubble-verzending terugzetten (reset)',
  })
end

return M
