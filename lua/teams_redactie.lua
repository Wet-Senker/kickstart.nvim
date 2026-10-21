-- Dunne, asynchrone client van teams-config. Geen automatische herstelwrites.
local M = {}
local commands = require('texttools_commands')
local dialog = require('user_dialog')
local workflow = require('workflow_log')
local notifications = require('texttools_notify')
local busy, notices_busy, timer, initialized = false, false, nil, false

local function call(args, done)
  local cmd = { commands.bin('teams-config') }
  vim.list_extend(cmd, args)
  local trace = workflow.start(nil, 'Teams · ' .. args[1], { command = 'teams-config' })
  local function fail(message)
    workflow.finish(trace, 'failed')
    notifications.notify(message, vim.log.levels.ERROR)
    done(nil)
  end
  local ok = pcall(vim.system, cmd, { text = true, timeout = 10000 }, notifications.schedule_wrap(function(result)
    local decoded, data = pcall(vim.json.decode, result.stdout or '')
    if result.code ~= 0 or not decoded or type(data) ~= 'table' or data.version ~= 1 then
      fail('Teams-instelling controleren/bijwerken mislukt: ' .. vim.trim(result.stderr or 'ongeldig antwoord'))
      return
    end
    workflow.finish(trace, 'succeeded')
    done(data)
  end))
  if not ok then fail('Teams-controle kon niet starten.') end
end
M._call = call

local function email(value) return type(value) == 'string' and value ~= '' and value or nil end
local function label(config, address)
  if not email(address) then return 'geen melding' end
  for _, person in ipairs(config.recipient_choices or {}) do
    if person.email:lower() == address:lower() then
      return person.name == address and address or person.name .. ' <' .. address .. '>'
    end
  end
  return address
end

function M.open()
  if busy then notifications.notify('Beantwoord eerst het openstaande Teams-menu.'); return end
  busy = true
  local function finish() busy = false end
  M._call({ 'show' }, function(config)
    if not config or type(config.editions) ~= 'table' then finish(); return end
    local items = { { kind = 'toggle', label = config.enabled ~= false and 'Meldingen: AAN — alles uitzetten' or 'Meldingen: UIT — alles aanzetten' } }
    for code, entry in pairs(config.editions) do
      local status = (config.statuses or {})[code] or {}
      local duration = status.mode == 'coverage' and (email(status.return_on) and (' · herstellen op ' .. status.return_on) or ' · onbepaalde tijd') or ''
      local prefix = status.mode == 'coverage' and 'WAARNEMING: ' or (status.mode == 'disabled' and 'UITGEZET: ' or '')
      items[#items + 1] = { kind = 'edition', code = code, label = (entry.krant or code) .. ' → ' .. prefix .. label(config, entry.email) .. duration }
    end
    table.sort(items, function(a, b) if a.kind == 'toggle' then return true elseif b.kind == 'toggle' then return false else return a.code < b.code end end)
    dialog.select(items, { prompt = 'Teams-meldingen eindredactie:', native = true, format_item = function(item) return item.label end }, function(chosen)
      if not chosen then finish(); return end
      local function saved(data)
        finish()
        if data then
          notifications.notify('Teams-instelling opgeslagen.', vim.log.levels.INFO)
          if initialized then M.check() end
        end
      end
      if chosen.kind == 'toggle' then
        M._call({ 'set-enabled', config.enabled ~= false and 'off' or 'on' }, saved)
        return
      end
      local code, entry = chosen.code, config.editions[chosen.code]
      local choices = { { kind = 'default', label = 'Standaardontvanger — ' .. label(config, entry.default_email) } }
      if type(entry.coverage) == 'table' then choices[#choices + 1] = { kind = 'restore', label = 'Vorige instelling herstellen — ' .. label(config, entry.coverage.previous_email) } end
      for _, person in ipairs(config.recipient_choices or {}) do
        choices[#choices + 1] = { kind = 'recipient', email = person.email, label = label(config, person.email) }
      end
      choices[#choices + 1] = { kind = 'off', label = 'Geen melding voor deze editie' }
      choices[#choices + 1] = { kind = 'new', label = 'Nieuwe vervanger toevoegen…' }
      choices[#choices + 1] = { kind = 'back', label = '← Terug naar krantenoverzicht' }
      local function save_recipient(address)
        local args = { 'set-recipient', code, '--expected-revision', config.revisions[code] }
        vim.list_extend(args, address and { '--email', address } or { '--off' })
        M._call(args, saved)
      end
      local function duration(address, name)
        require('date_picker').choose({ today = config.today, suggested = config.suggested_return_date, offset = 1, indefinite = true,
          prompt = 'Wanneer de vorige Teams-instelling voor ' .. (entry.krant or code) .. ' weer voorstellen?' }, function(day)
          if not day then finish(); return end
          local args = { name and 'add-recipient' or 'set-coverage', code, '--email', address,
            '--expected-revision', config.revisions[code] }
          if name then vim.list_extend(args, { '--name', name }) end
          vim.list_extend(args, day == 'indefinite' and { '--indefinite' } or { '--return-on', day })
          M._call(args, saved)
        end)
      end
      dialog.select(choices, { prompt = 'Teams-ontvanger voor ' .. (entry.krant or code) .. ':', native = true, format_item = function(item) return item.label end }, function(choice)
        if not choice then finish()
        elseif choice.kind == 'back' then finish(); vim.schedule(M.open)
        elseif choice.kind == 'default' then save_recipient(email(entry.default_email))
        elseif choice.kind == 'off' then save_recipient(nil)
        elseif choice.kind == 'restore' then M._call({ 'restore-coverage', code, '--coverage-id', entry.coverage.id }, saved)
        elseif choice.kind == 'recipient' then duration(choice.email)
        elseif choice.kind == 'new' then
          dialog.input({ prompt = 'Naam van de nieuwe vervanger:' }, function(name)
            if not name or vim.trim(name) == '' then finish(); return end
            dialog.input({ prompt = 'E-mailadres van ' .. vim.trim(name) .. ':' }, function(address)
              if not address or vim.trim(address) == '' then finish(); return end
              duration(vim.trim(address), vim.trim(name)) -- Python valideert het adres.
            end)
          end)
        end
      end)
    end)
  end)
end

function M.check()
  if notices_busy then return end
  notices_busy = true
  M._call({ 'notices' }, function(data)
    notices_busy = false
    if not data then return end
    if timer then
      if not timer:is_closing() then timer:stop(); timer:close() end
      timer = nil
    end
    if initialized and type(data.next_check_ms) == 'number' then
      timer = vim.defer_fn(M.check, data.next_check_ms)
    end
    local indefinite = {}
    for _, notice in ipairs(data.notices or {}) do
      if notice.kind == 'due' then
        local item = notice
        dialog.select({ 'Akkoord: vorige instelling herstellen', 'Niet herstellen; waarneming behouden' }, {
          prompt = (item.krant or item.edition) .. ': hersteldatum ' .. item.return_on .. ' bereikt.\n'
            .. 'Waarnemer: ' .. (email(item.email) or 'geen melding') .. '\n'
            .. 'Vorige instelling: ' .. (email(item.previous_email) or 'geen melding'),
          native = true, required = true,
        }, function(choice)
          workflow.decision(nil, 'Teams · Herstelvoorstel', choice and choice:find('Akkoord', 1, true) and 'restore' or 'retain', { item.edition })
          if choice and choice:find('Akkoord', 1, true) then
            M._call({ 'restore-coverage', item.edition, '--coverage-id', item.id }, function(config)
              if config then notifications.notify('Vorige Teams-instelling hersteld voor ' .. item.krant .. '.') end
            end)
          end
        end)
      elseif notice.kind == 'indefinite' then
        indefinite[#indefinite + 1] = (notice.krant or notice.edition) .. ' → ' .. (email(notice.email) or 'geen melding')
      end
    end
    if #indefinite > 0 then
      notifications.notify('Teams-waarneming voor onbepaalde tijd actief:\n' .. table.concat(indefinite, '\n') .. '\nAanpassen via :TeamsRedactie.', vim.log.levels.INFO)
    end
  end)
end

function M.setup()
  if initialized then return end
  initialized = true
  local function start()
    if #vim.api.nvim_list_uis() > 0 then M.check() end -- Geen statewrites/headless-startmeldingen.
  end
  if vim.v.vim_did_enter == 1 then vim.schedule(start)
  else vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(start) end }) end
end

return M
