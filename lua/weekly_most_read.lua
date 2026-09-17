-- Dunne NeoVim-client voor het meestgelezen weekoverzicht.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local browser = require 'ordered_browser'
local context_help = require 'context_help'

local command = { commands.bin 'python', '-m', 'texttools.weekly_most_read_cli', '--json' }

local editions = {
  { code = 'B', label = 'De Brug (B)' },
  { code = 'SW', label = 'De Swollenaer (SW)' },
  { code = 'ST', label = 'De Stadskoerier (ST)' },
  { code = 'D', label = 'De Drontenaar (D)' },
  { code = 'Z', label = 'Zeewolde Actueel (Z)' },
  { code = 'K', label = 'Nieuwsbode de Kop (K)' },
}

local function workflow(message, level, options)
  notifications.workflow(message, level, options)
end

local function open_editable(name, text, is_review)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(text, '\n', { plain = true })
  if lines[#lines] == '' then table.remove(lines) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'markdown'
  vim.bo[buf].bufhidden = 'hide'
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.cmd 'botright vsplit'
  vim.api.nvim_win_set_buf(0, buf)
  vim.b[buf].weekly_most_read_review = is_review == true
  return buf
end

local function decode(result, fallback)
  if result.code ~= 0 then
    vim.notify(
      vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr) or fallback,
      vim.log.levels.ERROR
    )
    return nil
  end
  local ok, data = pcall(vim.json.decode, vim.trim(result.stdout or ''))
  if not ok or type(data) ~= 'table' then
    vim.notify('Onleesbaar antwoord van het weekoverzicht.', vim.log.levels.ERROR)
    return nil
  end
  return data
end

local function facebook_links_needing_review(document)
  local selection = document:match(
    '<!%-%- selection%-start %-%->(.-)<!%-%- selection%-end %-%->'
  )
  if not selection then return {} end
  local selected = {}
  local count = 0
  for line in selection:gmatch('[^\n]+') do
    local rank = tonumber(
      line:match('^%s*LOS:%s*(%d+)%.') or line:match('^%s*(%d+)%.')
    )
    if rank and not selected[rank] then
      selected[rank] = true
      count = count + 1
    end
  end
  if count > 5 then return {} end

  local links = {}
  local parts = vim.split(document, '\n## Dossier ', { plain = true })
  for index = 2, #parts do
    local section = '## Dossier ' .. parts[index]
    local rank = tonumber(section:match('^## Dossier (%d+)%.'))
    local comments = tonumber(section:match('\nReacties:%s*(%d+)')) or 0
    local link = section:match('\nFacebook:%s*(https?://%S+)')
    local status = section:match('\nFacebookstatus:%s*([^\n]+)') or ''
    local reaction_text = section:match(
      '<!%-%- reactions%-start: %d+ %-%->%s*(.-)%s*<!%-%- reactions%-end: %d+ %-%->'
    ) or ''
    local still_empty = reaction_text == ''
      or reaction_text:find('Plak hier desgewenst de reacties', 1, true)
    if
      selected[rank]
      and comments >= 15
      and link
      and status:match('^handmatig:')
      and still_empty
    then
      table.insert(links, link)
    end
  end
  return links
end

local function photo_menu_items(photos)
  local items = {}
  local selected_count = 0
  for _, photo in ipairs(photos or {}) do
    if photo.choice ~= 'overslaan' then selected_count = selected_count + 1 end
  end
  if selected_count > 0 then
    table.insert(items, {
      label = string.format("Eén hoofdfoto van elk van de %d gekozen artikelen", selected_count),
      all_selected = true,
    })
  end
  for _, photo in ipairs(photos or {}) do
    table.insert(items, {
      label = string.format('%s · %s', tostring(photo.headline), tostring(photo.choice)),
      article_id = photo.article_id,
    })
  end
  return items
end

local function review_text(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
end

function M.prepare(edition)
  local cmd = vim.list_extend(vim.deepcopy(command), { 'prepare', '--edition', edition })
  workflow('Meestgelezen · artikelen en cijfers ophalen…', vim.log.levels.INFO)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      local data = decode(result, 'Meestgelezen weekoverzicht voorbereiden mislukt.')
      if not data or type(data.document) ~= 'string' then return end
      local buf = open_editable('Meestgelezen review ' .. edition, data.document, true)
      context_help.register(buf, {
        title = 'Meestgelezen weekoverzicht',
        lines = {
          '• Bovenaan staan maximaal tien kandidaten met alleen nummer en kop.',
          '• Verwijder ongewenste regels met dd; laat maximaal vijf regels staan.',
          '• De uiteindelijke volgorde wordt bepaald door het aantal keer bekeken.',
          '• Zet LOS: voor een regel voor een zelfstandig reactieartikel.',
          '• LOS: is alleen toegestaan vanaf 41 Facebookreacties.',
          '• Vanaf 15 reacties staat in het dossier een Facebooklink en plakvak.',
          '• Druk opnieuw <leader>kv om de overgebleven selectie te verwerken.',
          '• <leader>kf downloadt één hoofdfoto per gekozen artikel naar Bureaublad/meestgelezen.',
        },
      })
      vim.keymap.set('n', '<leader>kv', function() M.generate(buf) end, {
        buffer = buf,
        desc = '[K]rant [v]eelgelezen review verwerken',
      })
      vim.keymap.set('n', '<leader>kf', function() M.photos(buf) end, {
        buffer = buf,
        desc = '[K]rant meestgelezen [f]oto downloaden',
      })
      workflow(
        'Review geopend. Kies maximaal vijf regels; <leader>kv schrijft, <leader>kf downloadt hoofdfoto\'s. Hulp: <leader>kh.',
        vim.log.levels.INFO,
        { ttl = 12 }
      )
    end)
  end)
end

function M.generate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local text = review_text(buf)
  if not text then return end
  local links = facebook_links_needing_review(text)
  local review_key = table.concat(links, '\n')
  if #links > 0 and vim.b[buf].weekly_most_read_facebook_review_key ~= review_key then
    local choice = require('user_dialog').confirm(
      string.format(
        '%d gekozen artikel(en) hebben minimaal 15 reacties die nog niet zijn toegevoegd. Facebooklinks openen?',
        #links
      ),
      '&Ja, openen\n&Nee, zonder reacties doorgaan',
      1
    )
    vim.b[buf].weekly_most_read_facebook_review_key = review_key
    if choice == 1 then
      browser.open_urls(links)
      workflow(
        'Facebooklinks geopend. Plak desgewenst de reacties in de juiste dossiers en druk opnieuw <leader>kv.',
        vim.log.levels.INFO,
        { ttl = 12 }
      )
      return
    end
  end
  workflow('Meestgelezen · gecontroleerde tekst schrijven…', vim.log.levels.INFO)
  local cmd = vim.list_extend(vim.deepcopy(command), { 'generate' })
  vim.system(cmd, { text = true, stdin = text }, function(result)
    vim.schedule(function()
      local data = decode(result, 'Meestgelezen artikel genereren mislukt.')
      if not data then return end
      local opened = 0
      if type(data.overview) == 'string' and data.overview ~= '' then
        open_editable('Meestgelezen weekoverzicht ' .. tostring(data.edition), data.overview, false)
        opened = opened + 1
      end
      for index, item in ipairs(data.standalone or {}) do
        if type(item.article) == 'string' and item.article ~= '' then
          open_editable('Reactieartikel ' .. tostring(index) .. ' ' .. tostring(data.edition), item.article, false)
          opened = opened + 1
        end
      end
      workflow(
        string.format(
          '%d artikelbuffer(s) gemaakt; controleer en publiceer via de gewone flow.',
          opened
        ),
        vim.log.levels.INFO,
        { ttl = 10 }
      )
    end)
  end)
end

function M.photos(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.b[buf].weekly_most_read_review ~= true then
    vim.notify('Open eerst een meestgelezen-review met <leader>kv.', vim.log.levels.WARN)
    return
  end
  local text = review_text(buf)
  if not text then return end
  local list_cmd = vim.list_extend(vim.deepcopy(command), { 'photos', '--list' })
  workflow("Meestgelezen · beschikbare hoofdfoto's ophalen…", vim.log.levels.INFO)
  vim.system(list_cmd, { text = true, stdin = text }, function(result)
    vim.schedule(function()
      local data = decode(result, "Hoofdfoto's uitlezen mislukt.")
      if not data then return end
      local items = photo_menu_items(data.photos)
      if #items == 0 then
        vim.notify("Geen hoofdfoto's beschikbaar bij deze onderwerpen.", vim.log.levels.WARN)
        return
      end
      vim.ui.select(items, {
        prompt = "Van welke artikelen wil je één hoofdfoto?",
        format_item = function(item) return item.label end,
      }, function(choice)
        if not choice then return end
        local args = { 'photos' }
        if choice.all_selected then
          table.insert(args, '--all-selected')
        else
          vim.list_extend(args, { '--article-id', tostring(choice.article_id) })
        end
        vim.list_extend(args, { '--destination', vim.fn.expand('~/Desktop/meestgelezen') })
        local download_cmd = vim.list_extend(vim.deepcopy(command), args)
        workflow("Meestgelezen · hoofdfoto's downloaden…", vim.log.levels.INFO)
        vim.system(download_cmd, { text = true, stdin = text }, function(download_result)
          vim.schedule(function()
            local downloaded = decode(download_result, "Hoofdfoto's downloaden mislukt.")
            if not downloaded then return end
            workflow(
              string.format(
                "%d hoofdfoto('s) in Bureaublad/meestgelezen gezet.",
                tonumber(downloaded.count) or 0
              ),
              vim.log.levels.INFO,
              { ttl = 10 }
            )
          end)
        end)
      end)
    end)
  end)
end

function M.run()
  local buf = vim.api.nvim_get_current_buf()
  if vim.b[buf].weekly_most_read_review == true then
    M.generate(buf)
    return
  end
  vim.ui.select(editions, {
    prompt = 'Meestgelezen weekoverzicht voor welke krant?',
    format_item = function(item) return item.label end,
  }, function(choice)
    if choice then M.prepare(choice.code) end
  end)
end

function M.setup()
  if M._setup_done then return end
  M._setup_done = true
  vim.api.nvim_create_user_command('Meestgelezen', function() M.run() end, {
    desc = 'Meestgelezen weekoverzicht voorbereiden of genereren',
  })
  vim.api.nvim_create_user_command('MeestgelezenFotos', function() M.photos() end, {
    desc = "Eén hoofdfoto per artikel uit de huidige meestgelezen-review downloaden",
  })
  vim.keymap.set('n', '<leader>kv', M.run, {
    desc = '[K]rant [v]eelgelezen weekoverzicht',
  })
end

M._facebook_links_needing_review = facebook_links_needing_review
M._photo_menu_items = photo_menu_items

return M
