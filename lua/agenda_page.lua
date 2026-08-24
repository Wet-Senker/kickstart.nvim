local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'

local python = commands.bin 'python'
local module = 'texttools.agenda_page_cli'
local active_prepare = {}
local active_send = {}

local editions = {
  { code = 'B', label = 'De Brug (B)' },
  { code = 'SW', label = 'De Swollenaer (SW)' },
  { code = 'ST', label = 'De Stadskoerier (ST)' },
  { code = 'D', label = 'De Drontenaar (D)' },
  { code = 'Z', label = 'Zeewolde Actueel (Z)' },
  { code = 'K', label = 'Nieuwsbode de Kop (K)' },
}

local function workflow(message, level, options) notifications.workflow(message, level, options) end

local function buffer_text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end

function M.is_prepared(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  return buffer_text(buf):find('=== AGENDAPAGINA ===', 1, true) ~= nil
end

local function command(...)
  local result = { python, '-m', module }
  for _, value in ipairs { ... } do
    table.insert(result, value)
  end
  return result
end

local function progress(title)
  local ok, fidget = pcall(require, 'fidget.progress')
  if not ok or type(fidget.handle) ~= 'table' then return { finish = function() end } end
  return fidget.handle.create {
    title = title,
    message = '',
    lsp_client = { name = 'agenda-page' },
  }
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
  return decoded
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
  vim.notify('Agendapagina nog niet verzendklaar:\n- ' .. table.concat(errors, '\n- '), vim.log.levels.WARN)
  return false
end

local function validate_buffer(buf, callback, edition)
  local text = buffer_text(buf)
  local validate_command = edition and command('validate', '--edition', edition) or command 'validate'
  vim.system(validate_command, { text = true, stdin = text }, function(result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      local decoded = decode_validation(result.stdout)
      if not decoded then
        vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'De agendacontrole gaf geen leesbaar resultaat.', vim.log.levels.ERROR)
        if callback then callback(false) end
        return
      end
      local valid = show_validation(decoded)
      if callback then callback(valid, decoded) end
    end)
  end)
end

function M.prepare(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if active_prepare[buf] then
    workflow('De voorbereiding van deze agendapagina draait al.', vim.log.levels.INFO)
    return
  end
  if vim.trim(buffer_text(buf)) == '' then
    vim.notify('De huidige buffer is leeg.', vim.log.levels.ERROR)
    return
  end
  if M.is_prepared(buf) then
    workflow('Deze agendapagina is al voorbereid. Controleer de tekst en verzend met <leader>aw.', vim.log.levels.INFO)
    return
  end

  local original = buffer_text(buf)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  local handle = progress 'Agenda · Voorbereiden'
  local process
  process = vim.system(command 'prepare', { text = true, stdin = original }, function(result)
    handle:finish()
    active_prepare[buf] = nil
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.b[buf].agenda_prepare_cancelled then
        vim.b[buf].agenda_prepare_cancelled = false
        return
      end
      if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Voorbereiden van de agendapagina is mislukt.', vim.log.levels.ERROR)
        return
      end
      if vim.api.nvim_buf_get_changedtick(buf) ~= changedtick then
        vim.notify('De buffer veranderde tijdens de AI-bewerking; het resultaat is niet over de nieuwe tekst gezet.', vim.log.levels.WARN)
        return
      end
      replace_buffer(buf, result.stdout or '')
      workflow('Agendapagina voorbereid. Controleer de teksten en velden; verzend daarna met <leader>aw.', vim.log.levels.INFO, { ttl = 9 })
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
  vim.system(command 'preview', { text = true, stdin = buffer_text(buf) }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Blokpreview kon niet worden gemaakt.', vim.log.levels.ERROR)
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
  if active_send[buf] then
    workflow('De verzending van deze agendapagina loopt al.', vim.log.levels.INFO)
    return
  end
  if not M.is_prepared(buf) then
    vim.notify('Maak deze tekst eerst klaar met <leader>ka.', vim.log.levels.ERROR)
    return
  end

  active_send[buf] = true
  vim.ui.select(editions, {
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
        vim.notify('Sla de agendapagina eerst op als bestand.', vim.log.levels.ERROR)
        return
      end
      if vim.bo[buf].modified then
        local ok, error_message = pcall(vim.api.nvim_buf_call, buf, function() vim.cmd 'write' end)
        if not ok then
          active_send[buf] = nil
          vim.notify('Opslaan mislukt: ' .. tostring(error_message), vim.log.levels.ERROR)
          return
        end
      end
      if decoded.newspaper_article_id then
        active_send[buf] = nil
        workflow('Dit printconcept bestaat al in Pubble: ' .. tostring(decoded.newspaper_article_id), vim.log.levels.INFO)
        return
      end

      local handle = progress 'Agenda · Naar Pubble'
      vim.system(command('send', path, '--edition', edition.code), { text = true }, function(result)
        handle:finish()
        active_send[buf] = nil
        vim.schedule(function()
          if result.code ~= 0 then
            vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or 'Verzenden van de agendapagina is mislukt.', vim.log.levels.ERROR)
            return
          end
          local raw = (result.stdout or ''):match 'AGENDA_PAGE_RESULT_JSON:(%b{})'
          local ok, status = pcall(vim.json.decode, raw or '')
          if not ok or type(status) ~= 'table' then
            vim.notify('Pubble gaf geen leesbare verzendstatus terug.', vim.log.levels.ERROR)
            return
          end
          reload_after_send(buf)
          workflow('Printconcept !agendapagina aangemaakt: ' .. tostring(status.newspaper_article_id), vim.log.levels.INFO, { ttl = 9 })
        end)
      end)
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
  vim.api.nvim_create_user_command('AgendaPaginaPreview', function() M.preview() end, {
    desc = 'Pubble-blokken van de agendapagina bekijken',
  })
  vim.api.nvim_create_user_command('AgendaPaginaVersturen', function() M.send() end, {
    desc = 'Agendapagina print-only naar Pubble versturen',
  })
  vim.keymap.set('n', '<leader>ka', M.prepare, {
    desc = '[K]rant [A]gendapagina voorbereiden',
  })
end

M._command = command
M._decode_validation = decode_validation
M._replace_buffer = replace_buffer

return M
