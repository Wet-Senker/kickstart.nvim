local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local context_help = require 'context_help'

local python = commands.bin 'python'
local module = 'texttools.agenda_page_cli'
local active_prepare = {}
local active_send = {}
local active_measure = {}

-- Krantlijst uit één bron (Python's PUBLICATIONS), niet meer hardgecodeerd.
local editions_source = require('editions')

local function workflow(message, level, options) notifications.workflow(message, level, options) end

local function editor_base_url()
  local configured = vim.trim(vim.env.PUBBLE_EDITOR_BASE_URL or '')
  return (configured ~= '' and configured or 'https://brugmedia.pubble.nl'):gsub('/+$', '')
end

local function buffer_text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

function M.is_prepared(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  return buffer_text(buf):find('=== AGENDAPAGINA ===', 1, true) ~= nil
end

local function help_entry(buf)
  if active_send[buf] then
    return {
      title = 'Papieren agendapagina',
      status = 'Controle of verzending naar Pubble loopt.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { 'Wacht op de eindmelding; start geen tweede verzending.' },
        },
      },
    }
  end
  if active_prepare[buf] then
    return {
      title = 'Papieren agendapagina',
      status = 'De ruwe agenda wordt voorbereid.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { 'Wacht tot de zichtbare agendapagina is opgebouwd.' },
        },
        {
          heading = 'Andere hoofdopties',
          lines = { ':AgendaPaginaAnnuleren  Stop deze voorbereiding.' },
        },
        {
          heading = 'Let op',
          lines = { 'Wijzigingen tijdens de bewerking zorgen dat het late resultaat niet wordt toegepast.' },
        },
      },
    }
  end
  if not M.is_prepared(buf) then
    return {
      title = 'Papieren agendapagina',
      status = 'Ruwe agendatekst; nog niet voorbereid.',
      sections = {
        {
          heading = 'Nu doen',
          lines = { 'Plak alle dagen en activiteiten en druk eenmaal <leader>ka.' },
        },
        {
          heading = 'Daarna',
          lines = { 'De tekst wordt zichtbaar gestructureerd en geredigeerd; er wordt nog niets gepubliceerd.' },
        },
      },
    }
  end

  local validation = vim.b[buf].agenda_page_validation
  local published_url = vim.b[buf].agenda_page_published_url
  if type(published_url) == 'string' and published_url ~= '' then
    return {
      title = 'Papieren agendapagina',
      status = 'Het printconcept bestaat al in Pubble.',
      sections = {
        {
          heading = 'Nu doen',
          lines = {
            'Controleer het bestaande concept via de getoonde Pubble-link.',
            '<leader>aw herstelt veilig wanneer nog een koppeling ontbreekt; het maakt niet zomaar een tweede concept.',
          },
        },
      },
    }
  end
  if type(validation) == 'table' and validation.valid == false then
    local errors = type(validation.errors) == 'table' and validation.errors or {}
    return {
      title = 'Papieren agendapagina',
      status = 'Nog niet verzendklaar.',
      sections = {
        {
          heading = 'Nu doen',
          lines = #errors > 0 and errors or { 'Vul de ontbrekende of ongeldige velden in.' },
        },
        {
          heading = 'Daarna',
          lines = { 'Controleer opnieuw of druk <leader>aw; de technische controle draait vóór verzending.' },
        },
      },
    }
  end
  return {
    title = 'Papieren agendapagina',
    status = 'Voorbereid en zichtbaar ter redactionele controle.',
    sections = {
      {
        heading = 'Nu doen',
        lines = { 'Controleer per activiteit datum, titel, tijd, locatie en tekst.' },
      },
      {
        heading = 'Andere hoofdopties',
        lines = {
          '<leader>km / :AgendaPaginaOmvang  Tel alinea’s en schat hoeveel punten niet passen.',
          ':AgendaPaginaControleren  Voer de technische controle los uit.',
          ':AgendaPaginaPreview      Bekijk de Pubble-blokken.',
        },
      },
      {
        heading = 'Daarna',
        lines = {
          '<leader>aw  Kies de krant en maak uitsluitend het printconcept !agendapagina.',
        },
      },
    },
  }
end

local function register_help(buf)
  context_help.register(buf, function(target) return help_entry(target) end)
end

local function command(...)
  local result = { python, '-m', module }
  for _, value in ipairs { ... } do
    table.insert(result, value)
  end
  return result
end

local function progress(title, buf)
  local log = require('workflow_log')
  local trace = log.start(buf, title)
  return { finish = function(_, result)
    log.finish(trace, result.code == 0 and 'succeeded' or 'failed', { exit_code = result.code })
  end }
end

local function replace_buffer(buf, text)
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then table.remove(lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modified = true
end

local function decode_validation(stdout)
  local ok, decoded = pcall(vim.json.decode, vim.trim(stdout or ''))
  if not ok or type(decoded) ~= 'table' then return nil end
  -- vim.json.decode representeert JSON-null als het truthy userdata-object
  -- vim.NIL. Normaliseer optionele IDs, anders lijkt `null` op een bestaand
  -- Pubbleconcept en stopt de send vóór de API-call.
  if decoded.newspaper_article_id == vim.NIL then decoded.newspaper_article_id = nil end
  if decoded.article_join_id == vim.NIL then decoded.article_join_id = nil end
  if decoded.pubble_url == vim.NIL then decoded.pubble_url = nil end
  if decoded.duplicate_candidates == vim.NIL then decoded.duplicate_candidates = {} end
  return decoded
end

-- Read-only telling door dezelfde kern als de Pubble-export. Geen AI en geen
-- inhoudswijzigingen; één bronversie per resultaat, zonder meldingsregels.
function M.measure(buf, options)
  buf = buf or vim.api.nvim_get_current_buf()
  options = options or {}
  if not vim.api.nvim_buf_is_valid(buf) then return end
  register_help(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local function fingerprint()
    return vim.fn.sha256(table.concat(require('article_notices').content_lines(
      vim.api.nvim_buf_get_lines(buf, 0, -1, false)), '\n'))
  end
  local source = fingerprint()
  if options.automatic and vim.b[buf].agenda_page_measure_fingerprint == source then return end
  if active_measure[buf] and active_measure[buf].source == source then return end
  local request = { tick = tick, source = source }
  active_measure[buf] = request
  local log = require 'workflow_log'
  local trace = log.start(buf, 'Agenda · Omvang')
  local function finish(result)
    if request.finished then return end
    request.finished = true
    log.finish(trace, result.code == 0 and 'succeeded' or 'failed', { exit_code = result.code })
    notifications.schedule(function()
      if active_measure[buf] ~= request then return end
      active_measure[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if fingerprint() ~= source then
        if not options.automatic then
          workflow('Agenda gewijzigd tijdens het tellen; druk opnieuw <leader>km.',
            vim.log.levels.INFO, { buf = buf })
        end
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(data) ~= 'table' or data.version ~= 1
          or type(data.paragraphs) ~= 'number' or type(data.items) ~= 'number'
          or type(data.capacity) ~= 'number' or type(data.over_by) ~= 'number'
          or type(data.remove_items_estimate) ~= 'number' or type(data.message) ~= 'string' then
        workflow('Agendatelling mislukt; probeer opnieuw met <leader>km. '
          .. vim.trim(result.stderr or ''), vim.log.levels.WARN,
          { buf = buf, action = 'Agenda · Omvang' })
        return
      end
      vim.b[buf].agenda_page_measure_tick = tick
      vim.b[buf].agenda_page_measure_fingerprint = source
      vim.b[buf].agenda_page_capacity = data
      workflow(data.message, data.over_by > 0 and vim.log.levels.WARN or vim.log.levels.INFO,
        { buf = buf, action = 'Agenda · Omvang', resolved = true,
          kind = data.over_by == 0 and 'success' or nil })
    end)
  end
  local started, err = pcall(notifications.system, command 'measure',
    log.with_environment({ text = true, stdin = buffer_text(buf), timeout = 5000 }, trace), finish)
  if not started then finish { code = 1, stderr = tostring(err) } end
end

local function duplicate_candidate_line(candidate)
  return string.format(
    '%s: %s ↔ %s (%s, %d%%)',
    candidate.first_date or '?',
    candidate.first_title or '?',
    candidate.second_title or '?',
    candidate.reason or 'sterke overeenkomst',
    candidate.score or 0
  )
end

local function show_validation(decoded)
  if decoded.valid then
    workflow(
      string.format('Agendapagina klopt: %d dagen, %d activiteiten, editie %s.', decoded.days or 0, decoded.items or 0, decoded.edition or '?'),
      vim.log.levels.INFO
    )
    return true
  end
  local errors = decoded.errors or { 'Onbekende validatiefout' }
  notifications.notify('Agendapagina nog niet verzendklaar:\n- ' .. table.concat(errors, '\n- '), vim.log.levels.WARN)
  return false
end

local function validate_buffer(buf, callback, edition)
  local text = buffer_text(buf)
  local validate_command = edition and command('validate', '--edition', edition) or command 'validate'
  notifications.system(validate_command, { text = true, stdin = text }, function(result)
    notifications.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local decoded = decode_validation(result.stdout)
      if not decoded then
        notifications.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'De agendacontrole gaf geen leesbaar resultaat.', vim.log.levels.ERROR)
        if callback then callback(false) end
        return
      end
      vim.b[buf].agenda_page_validation = {
        valid = decoded.valid == true,
        errors = type(decoded.errors) == 'table' and decoded.errors or {},
      }
      if type(decoded.pubble_url) == 'string' and decoded.pubble_url ~= '' then
        vim.b[buf].agenda_page_published_url = decoded.pubble_url
      end
      local valid = show_validation(decoded)
      if callback then callback(valid, decoded) end
    end)
  end)
end

function M.prepare(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  register_help(buf)
  if active_prepare[buf] then
    workflow('De voorbereiding van deze agendapagina draait al.', vim.log.levels.INFO, { kind = 'progress' })
    return
  end
  if vim.trim(buffer_text(buf)) == '' then
    notifications.notify('De huidige buffer is leeg.', vim.log.levels.ERROR)
    return
  end
  if M.is_prepared(buf) then
    workflow('Deze agendapagina is al voorbereid. Controleer de tekst en verzend met <leader>aw.', vim.log.levels.INFO)
    M.measure(buf)
    return
  end

  -- Deze buffer is een print-agendapagina: houd 'm buiten de artikel-/online-
  -- agenda-/doubluredetectie van ai_text (die markers zijn het gedeelde
  -- contract). Zo verschijnt na <leader>ka niet alsnog de "naar de online agenda
  -- plaatsen?"-vraag die bij een gewoon artikel hoort.
  vim.b[buf].agenda_page_flow = true
  vim.b[buf].article_recognition_done = true
  vim.b[buf].calendar_autodetect_done = true
  M.measure(buf, { automatic = true })

  local original = buffer_text(buf)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local handle = progress('Agenda · Voorbereiden', buf)
  local process
  process = notifications.system(command 'prepare', { text = true, stdin = original }, function(result)
    handle:finish(result)
    active_prepare[buf] = nil
    notifications.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.b[buf].agenda_prepare_cancelled then
        vim.b[buf].agenda_prepare_cancelled = false
        return
      end
      if result.code ~= 0 then
        notifications.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Voorbereiden van de agendapagina is mislukt.', vim.log.levels.ERROR)
        return
      end
      if vim.api.nvim_buf_get_changedtick(buf) ~= changedtick then
        notifications.notify('De buffer veranderde tijdens de AI-bewerking; het resultaat is niet over de nieuwe tekst gezet.', vim.log.levels.WARN)
        return
      end
      replace_buffer(buf, result.stdout or '')
      workflow('Agendapagina voorbereid. Controleer de teksten en velden; verzend daarna met <leader>aw.', vim.log.levels.INFO,
        { buf = buf })
      M.measure(buf, { automatic = true })
    end)
  end)
  active_prepare[buf] = process
end

function M.cancel(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local process = active_prepare[buf]
  if not process or process:is_closing() then
    workflow('Geen agendavoorbereiding actief.', vim.log.levels.INFO)
    return
  end
  vim.b[buf].agenda_prepare_cancelled = true
  process:kill 'sigterm'
  active_prepare[buf] = nil
  workflow('Agendavoorbereiding geannuleerd.', vim.log.levels.INFO)
end

function M.validate(buf) validate_buffer(buf or vim.api.nvim_get_current_buf()) end

function M.preview(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  notifications.system(command 'preview', { text = true, stdin = buffer_text(buf) }, function(result)
    notifications.schedule(function()
      if result.code ~= 0 then
        notifications.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Blokpreview kon niet worden gemaakt.', vim.log.levels.ERROR)
        return
      end
      local readable = (result.stdout or ''):gsub('><', '>\n<')
      local lines = vim.split(vim.trim(readable), '\n', { plain = true })
      local preview = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(preview, 0, -1, false, lines)
      vim.bo[preview].filetype = 'html'
      vim.bo[preview].modifiable = false
      vim.cmd 'botright new'
      vim.api.nvim_win_set_buf(0, preview)
      vim.api.nvim_buf_set_name(preview, 'Agendapagina blokpreview')
    end)
  end)
end

local function reload_after_send(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_call(buf, function() vim.cmd 'silent edit' end)
end

function M.send(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  register_help(buf)
  if active_send[buf] then
    workflow('De verzending van deze agendapagina loopt al.', vim.log.levels.INFO, { kind = 'progress' })
    return
  end
  if not M.is_prepared(buf) then
    notifications.notify('Maak deze tekst eerst klaar met <leader>ka.', vim.log.levels.ERROR)
    return
  end

  active_send[buf] = true
  vim.ui.select(editions_source.list(), {
    prompt = 'Agendapagina versturen naar welke krant?',
    format_item = function(item) return item.label end,
  }, function(edition)
    if not edition or not vim.api.nvim_buf_is_valid(buf) then
      active_send[buf] = nil
      return
    end
    validate_buffer(buf, function(valid, decoded)
      if not valid then
        active_send[buf] = nil
        return
      end
      local path = vim.api.nvim_buf_get_name(buf)
      if path == '' then
        active_send[buf] = nil
        notifications.notify('Sla de agendapagina eerst op als bestand.', vim.log.levels.ERROR)
        return
      end
      if vim.bo[buf].modified then
        local ok, error_message = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd 'write' end)
        if not ok then
          active_send[buf] = nil
          notifications.notify('Opslaan mislukt: ' .. tostring(error_message), vim.log.levels.ERROR)
          return
        end
      end
      if decoded.pubble_url then
        active_send[buf] = nil
        vim.b[buf].agenda_page_published_url = decoded.pubble_url
        workflow('Agendapagina staat klaar voor plaatsing.\n' .. decoded.pubble_url, vim.log.levels.INFO, { ttl = 15 })
        return
      end

      local function run_send(allow_duplicates)
        local send_command = command('send', path, '--edition', edition.code)
        if allow_duplicates then table.insert(send_command, '--allow-duplicates') end
        local handle = progress('Agenda · Naar Pubble', buf)
        notifications.system(send_command, { text = true }, function(result)
          handle:finish(result)
          active_send[buf] = nil
          notifications.schedule(function()
            if result.code ~= 0 then
              notifications.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Verzenden van de agendapagina is mislukt.', vim.log.levels.ERROR)
              return
            end
            local raw = (result.stdout or ''):match 'AGENDA_PAGE_RESULT_JSON:(%b{})'
            local ok, status = pcall(vim.json.decode, raw or '')
            if not ok or type(status) ~= 'table' then
              notifications.notify('Pubble gaf geen leesbare verzendstatus terug.', vim.log.levels.ERROR)
              return
            end
            reload_after_send(buf)
            local article_url = status.article_url
              or (editor_base_url() .. '/articles/newspaper/' .. tostring(status.newspaper_article_id))
            vim.b[buf].agenda_page_published_url = article_url
            workflow('Agendapagina staat klaar voor plaatsing.\n' .. article_url, vim.log.levels.INFO, { ttl = 15 })
          end)
        end)
      end

      local duplicates = decoded.duplicate_candidates or {}
      if #duplicates > 0 then
        local lines = {}
        for _, candidate in ipairs(duplicates) do
          table.insert(lines, '• ' .. duplicate_candidate_line(candidate))
        end
        notifications.notify('Mogelijke doublures gevonden:\n' .. table.concat(lines, '\n'), vim.log.levels.WARN)
        vim.ui.select({
          { label = 'Annuleren', allow = false },
          { label = 'Toch verzenden', allow = true },
        }, {
          prompt = 'Zijn deze overeenkomsten gecontroleerd?',
          format_item = function(item) return item.label end,
        }, function(choice)
          if not choice or not choice.allow then
            active_send[buf] = nil
            return
          end
          run_send(true)
        end)
        return
      end
      run_send(false)
    end, edition.code)
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('AgendaPagina', function() M.prepare() end, {
    desc = 'Ruwe agendatekst voorbereiden in de huidige buffer',
  })
  vim.api.nvim_create_user_command('AgendaPaginaVoorbereiden', function() M.prepare() end, {
    desc = 'Ruwe agendatekst voorbereiden in de huidige buffer',
  })
  vim.api.nvim_create_user_command('AgendaPaginaAnnuleren', function() M.cancel() end, {
    desc = 'Lopende voorbereiding van een agendapagina annuleren',
  })
  vim.api.nvim_create_user_command('AgendaPaginaControleren', function() M.validate() end, {
    desc = 'Voorbereide agendapagina controleren',
  })
  vim.api.nvim_create_user_command('AgendaPaginaOmvang', function() M.measure() end, {
    desc = 'Agendablokken tellen en globale verwijderinschatting tonen (zonder AI)',
  })
  vim.api.nvim_create_user_command('AgendaPaginaPreview', function() M.preview() end, {
    desc = 'Pubble-blokken van de agendapagina bekijken',
  })
  vim.api.nvim_create_user_command('AgendaPaginaVersturen', function() M.send() end, {
    desc = 'Agendapagina print-only naar Pubble versturen',
  })
  vim.keymap.set('n', '<leader>ka', M.prepare, {
    desc = '[K]rant [a]gendapagina (print) voorbereiden',
  })
  vim.keymap.set('n', '<leader>km', M.measure, {
    desc = '[K]rant agendapagina [m]eten (zonder AI)',
  })
end

M._command = command
M._decode_validation = decode_validation
M._replace_buffer = replace_buffer
M._duplicate_candidate_line = duplicate_candidate_line
M._help_entry = help_entry

return M
