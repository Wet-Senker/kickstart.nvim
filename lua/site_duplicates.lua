-- Dunne NeoVim-client voor de site-interne webartikel-doublurecontrole.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local browser = require 'ordered_browser'

local python = commands.bin 'python'
local module = 'texttools.site_duplicates_cli'

local choices = {
  { code = 'all', label = 'Alle kranten (iedere site afzonderlijk)' },
  { code = 'B', label = 'De Brug' },
  { code = 'SW', label = 'De Swollenaer' },
  { code = 'ST', label = 'De Stadskoerier' },
  { code = 'D', label = 'De Drontenaar' },
  { code = 'Z', label = 'Zeewolde Actueel' },
  { code = 'K', label = 'Nieuwsbode de Kop' },
}

local function command(edition, include_reviewed)
  local result = { python, '-m', module, '--json', '--editie', edition or 'all' }
  if include_reviewed then table.insert(result, '--include-reviewed') end
  return result
end

local function mark_command()
  return { python, '-m', module, '--json', '--mark-reviewed' }
end

local function sanitize(value)
  return tostring(value or ''):gsub('[\r\n]+', ' ')
end

function M._render(result)
  local lines = {
    string.format('Webartikel-doublures (%s..%s; maximaal %s dagen uiteen)',
      result.from or '?', result.to or '?', result.max_days_apart or '?'),
    string.rep('=', 68),
    '',
  }
  for _, site in ipairs(result.sites or {}) do
    if site.error and site.error ~= vim.NIL then
      table.insert(lines, string.format('%s: NIET gelezen — %s',
        site.publication or site.edition, sanitize(site.error)))
    else
      local pairs = site.pairs or {}
      table.insert(lines, string.format('%s: %d actieve artikelen, %d mogelijke doublure(s)%s',
        site.publication or site.edition, site.article_count or 0, #pairs,
        #pairs > 0 and ':' or '.'))
      for _, pair in ipairs(pairs) do
        table.insert(lines, string.format('  %s%s (%s) ↔ %s (%s)',
          pair.reviewed and '[gecontroleerd] ' or '',
          sanitize(pair.left.headline), pair.left.display_date_label or '?',
          sanitize(pair.right.headline), pair.right.display_date_label or '?'))
        table.insert(lines, string.format('      %s; %d dag(en) uiteen (%d%%)',
          sanitize(pair.reason), pair.days_apart or 0, pair.score or 0))
        table.insert(lines, '      ' .. tostring(pair.left.editor_url))
        table.insert(lines, '      ' .. tostring(pair.right.editor_url))
      end
      if (site.reviewed_hidden_count or 0) > 0 then
        table.insert(lines, string.format('  %d eerder gecontroleerde kandidaatpaar(en) verborgen.',
          site.reviewed_hidden_count))
      end
      if site.truncated then
        table.insert(lines, '  Let op: kandidaatlimiet bereikt; verklein zo nodig de periode.')
      end
      if (site.detail_errors or 0) > 0 then
        table.insert(lines, string.format('  %d artikel(en) konden niet volledig worden gelezen.',
          site.detail_errors))
      end
    end
    table.insert(lines, '')
  end
  table.insert(lines, '<leader>km = getoonde lichting markeren als gecontroleerd')
  table.insert(lines, '<leader>ka = eerder gecontroleerde kandidaatparen tonen/verbergen')
  return lines
end

local function review_keys(result)
  local keys = {}
  for _, site in ipairs(result.sites or {}) do
    for _, pair in ipairs(site.pairs or {}) do
      if pair.review_key then table.insert(keys, pair.review_key) end
    end
  end
  return keys
end

local function mark_result(result, on_done)
  local keys = review_keys(result)
  if #keys == 0 then
    vim.notify('Deze lichting bevat geen kandidaatparen om te markeren.', vim.log.levels.INFO)
    return
  end
  vim.system(mark_command(), {
    text = true,
    stdin = vim.json.encode { review_keys = keys },
  }, function(process)
    vim.schedule(function()
      if process.code ~= 0 then
        vim.notify(vim.trim(process.stderr or '') ~= '' and vim.trim(process.stderr)
          or 'Markeren als gecontroleerd mislukt.', vim.log.levels.ERROR)
        return
      end
      local ok, response = pcall(vim.json.decode, vim.trim(process.stdout or ''))
      if not ok or type(response) ~= 'table' then
        vim.notify('Onleesbaar antwoord bij het markeren.', vim.log.levels.ERROR)
        return
      end
      notifications.workflow(string.format(
        '%d kandidaatpaar(en) gemarkeerd als gecontroleerd.', response.marked_count or #keys),
        vim.log.levels.INFO, { ttl = 10 })
      if on_done then on_done() end
    end)
  end)
end

local function show_report(result, edition, include_reviewed)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M._render(result))
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, 'Webartikel-doublures')
  vim.cmd 'botright vsplit'
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set('n', '<leader>km', function()
    mark_result(result, function()
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end)
  end, { buffer = buf, desc = 'Lichting als gecontroleerd markeren' })
  vim.keymap.set('n', '<leader>ka', function()
    if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    M.run(edition, { include_reviewed = not include_reviewed, open_browser = false })
  end, { buffer = buf, desc = 'Gecontroleerde webdoublures tonen/verbergen' })
end

function M.run(edition, options)
  edition = edition or 'all'
  options = options or {}
  notifications.workflow('Webartikelen · doublures zoeken…', vim.log.levels.INFO)
  vim.system(command(edition, options.include_reviewed), { text = true }, function(process)
    vim.schedule(function()
      if process.code ~= 0 then
        vim.notify(vim.trim(process.stderr or '') ~= '' and vim.trim(process.stderr)
          or 'Webdoublurecontrole mislukt.', vim.log.levels.ERROR)
        return
      end
      local ok, result = pcall(vim.json.decode, vim.trim(process.stdout or ''))
      if not ok or type(result) ~= 'table' then
        vim.notify('Onleesbare JSON van de webdoublurecontrole.', vim.log.levels.ERROR)
        return
      end
      show_report(result, edition, options.include_reviewed == true)
      local urls = {}
      for _, site in ipairs(result.sites or {}) do
        vim.list_extend(urls, site.open_urls or {})
      end
      if options.open_browser ~= false then browser.open_urls(urls) end
      notifications.workflow(string.format(
        options.open_browser == false
          and 'Webdoublurecontrole klaar: rapport bijgewerkt.'
          or 'Webdoublurecontrole klaar: %d artikel(en) geordend in de browser geopend.',
        #urls),
        vim.log.levels.INFO, { ttl = 10 })
    end)
  end)
end

function M.menu()
  vim.ui.select(choices, {
    prompt = 'Welke krant(en) op interne webdoublures controleren?',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then M.run(choice.code) end
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('WebDoublures', function(opts)
    M.run(opts.args ~= '' and opts.args or 'all')
  end, {
    nargs = '?',
    complete = function() return { 'all', 'B', 'SW', 'ST', 'D', 'Z', 'K' } end,
    desc = 'Zoek actieve webartikel-doublures binnen één of alle sites',
  })
  vim.keymap.set('n', '<leader>kd', M.menu, {
    desc = '[K]rant web[d]oublures (per site)',
  })
end

M._command = command
M._mark_command = mark_command
M._review_keys = review_keys

return M
