-- Thin async client. Search rules, durable selection and metadata live in Python.
local M = {}
local commands = require 'texttools_commands'
local dialog = require 'user_dialog'
local notifications = require('texttools_notify')
local notify = notifications.workflow
local workflow_log = require 'workflow_log'
local browser = require 'ordered_browser'
local sessions = {}
local render
local ai_prompt
local ai_import

local function one_line(value)
  return tostring(value or ''):gsub('%c', ' ')
end

local function text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') .. '\n'
end

local function copy_to_clipboard(value)
  vim.fn.setreg('"', value)
  if vim.fn.has('mac') == 1 and vim.fn.executable('/usr/bin/pbcopy') == 1 then
    vim.fn.system({ '/usr/bin/pbcopy' }, value)
    return vim.v.shell_error == 0
  end
  local ok = pcall(vim.fn.setreg, '+', value)
  return ok and vim.fn.getreg('+') == value
end

local function current(s)
  return sessions[s.source] == s and not s.closed
    and vim.api.nvim_buf_is_valid(s.source)
    and vim.api.nvim_buf_is_loaded(s.source)
    and vim.bo[s.source].modifiable and not vim.bo[s.source].readonly
    and vim.b[s.source].publication_in_progress ~= true
end

local function stop_ai_resume(s)
  s.ai_waiting = false
  if s.ai_resume_autocmd then
    pcall(vim.api.nvim_del_autocmd, s.ai_resume_autocmd)
    s.ai_resume_autocmd = nil
  end
end

local function photo_context(s)
  local buf = vim.api.nvim_get_current_buf()
  return buf == s.source or buf == s.buffer
end

local function run(s, args, input, done, on_error, merges_left)
  if s.busy then return end
  s.busy = true
  local cmd = { commands.bin('python'), '-m', 'texttools.pubble_photo_cli' }
  vim.list_extend(cmd, args)
  local action = args[1]
  local request_tick = vim.api.nvim_buf_get_changedtick(s.source)
  local mutates = action == 'select' or action == 'ai-import' or action == 'merge'
  local labels = { search = 'Foto · Zoeken', ['ai-prompt'] = 'Foto · AI-prompt',
    ['ai-inbox-baseline'] = 'Foto · AI-Inbox beginsituatie', ['ai-inbox'] = 'Foto · AI-Inbox controleren',
    ['ai-import'] = 'Foto · AI-stock importeren', ['merge'] = 'Foto · Nieuwste tekst behouden' }
  local trace = labels[action] and workflow_log.start(s.source, labels[action], {
    command = 'pubble-photo ' .. action,
  }) or nil
  local options = { text = true, stdin = input }
  if action == 'ai-inbox' or action == 'ai-inbox-baseline' or action == 'ai-import' or action == 'ai-import-finalize' then options.timeout = 60000 end
  if trace then options = workflow_log.with_environment(options, trace) end
  local function finish(outcome, detail)
    if trace then workflow_log.finish(trace, outcome, detail); trace = nil end
  end
  local function failed(message)
    notify(message, vim.log.levels.ERROR, { ttl = 15 })
    if on_error then on_error(message) end
  end
  local ok, err = pcall(notifications.system, cmd, options, function(result)
    notifications.schedule(function()
      s.busy = false
      s.process = nil
      if s.closed or sessions[s.source] ~= s then
        finish('cancelled', { reason = 'photo_session_closed' })
        return
      end
      if not current(s) then
        stop_ai_resume(s)
        finish('stale', { reason = 'buffer_changed' })
        notify('Fotoactie gestopt: verzending gestart of artikel niet meer bewerkbaar. Er is niets overschreven.', vim.log.levels.WARN)
        return
      end
      local decoded, data = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not decoded or type(data) ~= 'table' or (data.version ~= 1 and data.version ~= 2) then
        finish('failed', { exit_code = result.code,
          reason = action == 'search' and 'search_result_failed' or 'import_result_failed' })
        failed(result.code == 124 and "Inbox-import duurde te lang. Controleer of iCloud de foto's volledig heeft gedownload en probeer opnieuw."
          or vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
          or 'Fotokeuze mislukt; artikel is niet gewijzigd.')
        return
      end
      local detail = { location_id = data.stock_location_id,
        candidate_count = type(data.photos) == 'table' and #data.photos or nil,
        keyword_count = type(data.keywords) == 'table' and #data.keywords or nil }
      if mutates and vim.api.nvim_buf_get_changedtick(s.source) ~= request_tick then
        local remaining = merges_left == nil and 2 or merges_left
        if remaining == 0 then
          finish('stale', { reason = 'continuous_buffer_changes' })
          failed('Het artikel blijft veranderen. De foto is nog niet gekoppeld; kies haar opnieuw als de bewerking klaar is.')
          return
        end
        local valid, payload = pcall(vim.json.decode, input or '')
        if not valid or type(payload.markdown) ~= 'string' or type(data.markdown) ~= 'string' then
          finish('failed', { reason = 'invalid_merge_input' })
          failed('Fotoresultaat kan niet veilig worden samengevoegd; niets overschreven.')
          return
        end
        finish('succeeded', detail)
        -- Rebase only media through the shared Python action. Never rerun an
        -- Inbox import (copy/create), and never replace newer article content.
        run(s, { 'merge' }, vim.json.encode({ markdown = text(s.source),
          original_markdown = payload.markdown, prepared_markdown = data.markdown }), function(merged)
          data.markdown = merged.markdown
          done(data)
        end, on_error, remaining - 1)
        return
      end
      done(data)
      finish('succeeded', detail)
    end)
  end)
  if not ok then
    s.busy = false
    finish('failed', { reason = 'process_start_failed' })
    failed('Fotokeuze kon niet starten: ' .. tostring(err))
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
  stop_ai_resume(s)
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
  if not confirmed then
    local tick = vim.api.nvim_buf_get_changedtick(s.source)
    dialog.confirm_async('Deze foto gebruiken? Controleer context en gebruiksrechten.\n\n'
        .. photo.source_title .. '\nCredit: ' .. credit .. '\nBijschrift: ' .. caption,
        '&Ja\n&Nee', 2, false, function(answer)
          if answer ~= 1 or not current(s) then return end
          if vim.api.nvim_buf_get_changedtick(s.source) ~= tick then
            notify('Artikel gewijzigd tijdens de fotobevestiging. Kies de foto opnieuw.', vim.log.levels.WARN, { buf = s.source })
            return
          end
          choose(s, photo, true)
        end, { source_buf = s.source })
    return
  end
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
    notify(saved and 'Foto gekozen. Controleer c: (verplicht); b: is optioneel. Daarna <leader>aw om te verzenden.'
      or 'Foto staat in de buffer, maar opslaan mislukte. Sla eerst op; controleer c: (verplicht), daarna <leader>aw.',
      saved and vim.log.levels.INFO or vim.log.levels.WARN, { ttl = 12 })
  end)
end

local function open_browser_choice(s)
  if s.busy or not current(s) then return end
  if not s.data or not s.photos then
    notify('Geen zoekresultaten geladen. Zoek eerst met s.', vim.log.levels.INFO)
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
      notify('Browserkeuze gestopt: verzending gestart of artikel niet meer bewerkbaar.', vim.log.levels.WARN)
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
          -- action and media-only merge guard still apply; never auto-send.
          choose(s, photo, true)
          return
        end
      end
      stop_browser(s)
      notify('Deze browserkeuze hoort niet bij de huidige zoekpagina.', vim.log.levels.WARN)
    elseif data.event == 'page' and type(data.page) == 'table' and type(data.page.photos) == 'table' then
      render(s, data.page)
    elseif data.event == 'action' and data.action == 'ai' then
      ai_prompt(s)
    elseif data.event == 'action' and data.action == 'import' then
      ai_import(s)
    elseif data.event == 'expired' then
      stop_browser(s)
      notify('Foto-overzicht verlopen. Druk p voor een nieuw overzicht.', vim.log.levels.INFO)
    end
  end
  local cmd = { commands.bin('python'), '-m', 'texttools.pubble_photo_cli', 'browse' }
  local ok, process = pcall(notifications.system, cmd, {
    text = true, stdin = vim.json.encode({ photos = s.photos, page = s.data }),
    stdout = function(err, chunk)
      if err or not chunk then return end
      session.pending = session.pending .. chunk
      while session.pending:find('\n', 1, true) do
        local ending = session.pending:find('\n', 1, true)
        local line = session.pending:sub(1, ending - 1)
        session.pending = session.pending:sub(ending + 1)
        local decoded, data = pcall(vim.json.decode, line)
        if decoded and type(data) == 'table' then notifications.schedule(function() event(data) end) end
      end
    end,
  }, function(result)
    notifications.schedule(function()
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

ai_prompt = function(s)
  if s.busy or s.stock_form_open or not current(s) then return end
  run(s, { 'ai-prompt' }, text(s.source), function(data)
    if type(data.prompt) ~= 'string' or type(data.chatgpt_url) ~= 'string' then return end
    dialog.input({
      prompt = 'AI-stockprompt controleren · Enter: kopiëren en ChatGPT openen',
      default = data.prompt,
      vim_edit = true,
    }, function(prompt)
      if not prompt or vim.trim(prompt) == '' or not current(s) then return end
      -- Record existing files before the browser opens. Python owns file
      -- selection/identity, including moves by the local Inbox watcher.
      stop_ai_resume(s)
      run(s, { 'ai-inbox-baseline' }, vim.json.encode({ markdown = text(s.source),
        article_path = vim.api.nvim_buf_get_name(s.source) }), function(baseline)
        if type(baseline.baseline) ~= 'table' then
          notify('AI-Inbox kon niet worden voorbereid. Open de fotokeuze opnieuw.', vim.log.levels.ERROR)
          return
        end
        s.ai_baseline = baseline.baseline
        s.ai_waiting = true
        s.ai_resume_autocmd = vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
          desc = 'AI-fototags aanbieden bij terugkeer naar het artikel',
          callback = function()
            notifications.schedule(function()
              if s.ai_waiting and not s.busy and not s.stock_form_open and photo_context(s) then
                ai_import(s, true)
              end
            end)
          end,
        })
        local copied = copy_to_clipboard(prompt)
        if browser.open_urls({ data.chatgpt_url }) then
          notify(copied
            and 'Beeldprompt gekopieerd. Zet de AI-download in Pubble Inbox; bij terugkeer opent het tagscherm. Weggeklikt? Druk i in de fotokeuze.'
            or 'ChatGPT is geopend, maar het systeemklembord werkte niet. De prompt staat wel in het gewone Vim-register.',
            copied and vim.log.levels.INFO or vim.log.levels.WARN, { ttl = 15 })
        else
          stop_ai_resume(s)
          notify('Prompt staat op het klembord, maar ChatGPT kon niet worden geopend. Importeer later met i.', vim.log.levels.WARN)
        end
      end)
    end)
  end)
end

ai_import = function(s, automatic)
  if s.busy or s.stock_form_open then return end
  if not current(s) then
    stop_ai_resume(s)
    notify('Fotoactie gestopt: verzending gestart of artikel niet meer bewerkbaar. Er is niets overschreven.', vim.log.levels.WARN)
    return
  end
  if not automatic then stop_ai_resume(s) end
  local article_path = vim.api.nvim_buf_get_name(s.source)
  if article_path == '' then
    notify('Sla het artikel eerst op voordat je een AI-stockfoto importeert.', vim.log.levels.WARN)
    return
  end
  local function import_error(message)
    stop_ai_resume(s)
    if not current(s) then return end
    dialog.select({ 'Opnieuw proberen', 'Terug naar fotokeuze' }, {
      prompt = 'AI-stockimport niet gelukt:\n' .. message .. '\nJe ingevoerde tags blijven bewaard.', native = true,
    }, function(choice) if choice == 'Opnieuw proberen' then ai_import(s) end end)
  end
  run(s, { 'ai-inbox' }, vim.json.encode({ markdown = text(s.source), article_path = article_path,
    new_since = s.ai_baseline, allow_empty = automatic == true }), function(snapshot)
    if automatic and not photo_context(s) then return end
    if type(snapshot.files) ~= 'table' then import_error("Inbox gaf geen bruikbare fotolijst terug."); return end
    if #snapshot.files == 0 then
      if not automatic then import_error("Inbox gaf geen bruikbare foto's terug.") end
      return -- Keep waiting for the next focus return; no polling or empty popup.
    end
    stop_ai_resume(s)
    local names = {}
    for index, file in ipairs(snapshot.files) do names[#names + 1] = index .. '. ' .. one_line(file.name) end
    local prompt = 'AI-stockimport · ' .. #snapshot.files .. ' Inbox-foto(' .. (#snapshot.files == 1 and '' or "'s") .. ')\n'
      .. table.concat(names, '\n') .. "\nAlle foto's krijgen dezelfde tags, illustratief bijschrift en AI-credit.\n"
      .. 'Vul alleen de tags in (of plak de ARCHIEFTAGS-regel). Enter: importeren.'
    if type(snapshot.duplicate_count) == 'number' and snapshot.duplicate_count > 0 then
      prompt = prompt .. '\n' .. snapshot.duplicate_count .. ' identieke kopie(ën) worden één keer geïmporteerd en herstelbaar weggezet.'
    end
    s.stock_form_open = true
    dialog.input({ prompt = 'AI-stockfoto · alleen archieftags', description = prompt,
      footer = ' Esc: Normal | Enter: importeren | Ctrl-C: annuleren ',
      default = s.stock_tags or '', vim_edit = true }, function(value)
      s.stock_form_open = false
      if value == nil or not current(s) then return end
      s.stock_tags = value
      run(s, { 'ai-import' }, vim.json.encode({ markdown = text(s.source), article_path = article_path,
        files = snapshot.files, tags = value }), function(data)
        if type(data.markdown) ~= 'string' or not current(s) then return end
        vim.api.nvim_buf_set_lines(s.source, 0, -1, false,
          vim.split(data.markdown:gsub('\n$', ''), '\n', { plain = true }))
        local source = s.source
        close(s)
        vim.api.nvim_set_current_buf(source)
        local saved = pcall(vim.cmd, 'silent update')
        workflow_log.diagnostic(source, 'Foto · AI-stock vastgelegd', {
          status = saved and 'saved' or 'save_failed', location_id = data.stock_location_id,
          image_count = data.image_count, keyword_count = type(data.keywords) == 'table' and #data.keywords or 0,
        })
        if not saved then
          notify("Foto's staan in de buffer, maar opslaan mislukte.\nSla het artikel op met :w vóór <leader>aw. Inbox-originelen blijven staan.",
            vim.log.levels.ERROR, { buf = source, attention = true })
          return
        end
        notify(tostring(data.image_count or #snapshot.files) .. ' AI-stockfoto(' .. (#snapshot.files == 1 and '' or "'s")
          .. ") geïmporteerd voor algemene beeldbank 24. Dezelfde tags voor alle foto's. Verzenden blijft handmatig.", vim.log.levels.INFO, { ttl = 15 })
        if type(data.batch_id) == 'string' then
          -- Pas na duurzaam opslaan de originelen herstelbaar wegzetten. Geen
          -- bufferwrite in deze callback; nieuwe redactiebewerkingen blijven veilig.
          local cmd = { commands.bin('python'), '-m', 'texttools.pubble_photo_cli', 'ai-import-finalize' }
          local ok = pcall(notifications.system, cmd, { text = true, stdin = vim.json.encode({ article_path = article_path, batch_id = data.batch_id }) }, notifications.schedule_wrap(function(result)
            if result.code ~= 0 then
              notify('Stockkopieën zijn geïmporteerd, maar Inbox-originelen konden niet volledig worden weggezet.\n'
                .. vim.trim(result.stderr or '') .. "\nDe foto's blijven herstelbaar; controleer de Inbox vóór een volgend artikel.",
                vim.log.levels.WARN, { buf = source, attention = true })
            end
          end))
          if not ok then notify('Import gelukt, maar Inbox-originelen zijn nog niet weggezet.', vim.log.levels.WARN, { ttl = 15 }) end
        end
      end, import_error)
    end)
  end, import_error)
end

local search
local function ask_query(s, initial)
  if s.busy or not current(s) then return end
  stop_browser(s)
  s.query_pending = true
  dialog.input({ prompt = s.search_help or (s.structured and 'Foto: Zoekwoorden met komma’s, bijvoorbeeld biljart, Kampen; los én gecombineerd gezocht' or 'Pubble-foto’s zoeken'),
    default = initial or s.editor_text or s.query or '', vim_edit = true,
    priority = true, source_buf = s.source,
    on_open = function(buf, win)
      s.input_win = win
      vim.b[buf].pubble_photo_source = s.source
    end,
  }, function(query)
    s.query_pending = false
    s.input_win = nil
    if not current(s) then
      if not s.closed then
        notify('Fotoactie gestopt: verzending gestart of artikel niet meer bewerkbaar. Er is niets overschreven.', vim.log.levels.WARN)
      end
      return
    end
    -- Preserve field lines; only legacy input is flattened. Python owns rules.
    query = query and vim.trim(s.structured and query or query:gsub('%s+', ' ')) or nil
    if query and query ~= '' then
      search(s, query, 0)
    elseif not s.buffer then
      close(s)
    end
  end)
end

render = function(s, data)
  s.data = data
  if data.query then s.query = data.query end
  if data.editor_text then s.editor_text = data.editor_text end
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
    map('p', function() open_browser_choice(s) end, 'Alle voorbeelden in browser bekijken en kiezen')
    map('s', function() ask_query(s) end, 'Andere zoekwoorden')
    map('a', function() ai_prompt(s) end, 'Nieuwe AI-stockfoto maken via ChatGPT')
    map('i', function() ai_import(s) end, 'AI-fototags (opnieuw) openen en importeren')
    map('b', function()
      if s.busy or not current(s) or not s.data or not s.data.fields then return end
      local next_source = ({
        articles = 'Beeldbank',
        images = 'Beide',
        both = "Artikelfoto's",
      })[s.data.fields.source] or 'Beide'
      local updated = (s.editor_text or ''):gsub('^Bron:[^\n]*', 'Bron: ' .. next_source)
      search(s, updated, 0)
    end, 'Wissel bron: artikelfoto’s, beeldbank, beide')
    map(']p', function()
      if type(s.next_offset) == 'number' then search(s, s.editor_text or s.query, s.next_offset) end
    end, 'Meer resultaten toevoegen')
    map('q', function() close(s) end, 'Terug zonder fotokeuze')
  end
  s.rows = {}
  s.photos = data.photos or {}
  s.next_offset = data.next_offset
  local has_more = type(s.next_offset) == 'number'
  local source = data.source == 'images' and 'Beeldbank' or data.source == 'both' and 'Beide' or "Artikelfoto's"
  local route = type(data.query_count) == 'number' and (' · ' .. data.query_count .. ' zoekcombinaties') or ''
  local controls = 'p: foto-overzicht | b: bron | s: zoeken | a: AI-stock | i: tags/import | Enter: kies | q: terug'
  if has_more then controls = controls .. ' | ]p: meer laden' end
  local lines = { 'Pubble-foto’s · ' .. source .. ' · ' .. #s.photos .. ' gevonden' .. route,
    controls,
    'Controleer context en gebruiksrechten vóór selectie.', '' }
  for i, photo in ipairs(s.photos) do
    local label = one_line(photo.display_caption or photo.caption)
    if label == '' then label = one_line(photo.source_title) end
    table.insert(lines, string.format('%d. %s · %s', i, one_line(photo.edition), label))
    s.rows[#lines] = photo
    if i < #s.photos then table.insert(lines, '') end
  end
  if #s.photos == 0 then
    table.insert(lines, has_more
      and 'Geen foto’s op deze pagina. Met ]p controleer je de volgende bronresultaten.'
      or 'Geen foto’s gevonden. Probeer een andere bron of andere zoekwoorden.')
  end
  if has_more then
    table.insert(lines, '')
    table.insert(lines, 'Meer bronresultaten beschikbaar: ]p of de knop in de browser.')
  end
  vim.bo[s.buffer].modifiable = true
  vim.api.nvim_buf_set_lines(s.buffer, 0, -1, false, lines)
  vim.bo[s.buffer].modifiable = false
end

search = function(s, query, offset)
  if s.busy then return end
  stop_browser(s)
  local args = { 'search', '--query', query, '--offset', tostring(offset) }
  local input
  if s.structured then
    s.editor_text = query
    args = { 'search', '--fields', '--offset', tostring(offset) }
    local payload = { editor_text = query, hidden_sources = s.hidden }
    if offset > 0 and s.data and s.data.fields then
      payload.previous = { version = s.data.version or 1, fields = s.data.fields,
        candidates = s.data.candidates, next_offset = s.data.next_offset,
        query_strategy = s.data.query_strategy }
    end
    input = vim.json.encode(payload)
  else s.query = query end
  notify('Pubble-foto’s zoeken…', vim.log.levels.INFO, { kind = 'progress' })
  run(s, args, input, function(data)
    if offset == 0 then s.expanded = {} end
    render(s, data)
  end)
end

function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  buf = vim.b[buf].pubble_photo_source or vim.b[buf].user_dialog_source or buf
  if not vim.api.nvim_buf_is_valid(buf) then return end
  -- A review buffer owns only edition text, never article-level media/YAML.
  -- Resolve the same durable source used by the edition review client before
  -- starting any search, ordinary selection or AI-stock import.
  local edition_source = vim.b[buf].edition_source_buf
  if edition_source ~= nil then
    if type(edition_source) ~= 'number' or not vim.api.nvim_buf_is_valid(edition_source) then
      notify('Het hoofddocument van deze krantversie is niet meer open. Open dat document voor de fotokeuze.', vim.log.levels.WARN)
      return
    end
    buf = edition_source
    notify('De fotokeuze geldt voor het hoofddocument en alle krantversies.', vim.log.levels.INFO)
  end
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
  if existing and current(existing) then
    if existing.busy or existing.query_pending or existing.stock_form_open then
      notify('De fotokeuze is al actief.', vim.log.levels.INFO)
      return
    end
    if existing.buffer and vim.api.nvim_buf_is_valid(existing.buffer) then
      local win = vim.fn.bufwinid(existing.buffer)
      if win ~= -1 then vim.api.nvim_set_current_win(win) end
      return
    end
  end
  if existing then close(existing) end
  local source_win = vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_current_win() or vim.fn.bufwinid(buf)
  local s = { source = buf, source_win = source_win, hidden = {}, expanded = {} }
  sessions[buf] = s
  run(s, { 'suggest' }, text(buf), function(data)
    s.structured = type(data.editor_text) == 'string'
    s.search_help = data.field_help
    ask_query(s, data.editor_text or data.query)
  end)
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
