-- Dunne NeoVim-client voor het meestgelezen weekoverzicht.

local M = {}

local commands = require 'texttools_commands'
local notifications = require 'texttools_notify'
local browser = require 'ordered_browser'

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
    vim.notify(vim.trim(result.stderr or '') ~= '' and vim.trim(result.stderr)
      or fallback, vim.log.levels.ERROR)
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
  local links = {}
  local parts = vim.split(document, '\n## ', { plain = true })
  for index = 2, #parts do
    local section = '## ' .. parts[index]
    local comments = tonumber(section:match('\nReacties:%s*(%d+)')) or 0
    local link = section:match('\nFacebook:%s*(https?://%S+)')
    local status = section:match('\nFacebookstatus:%s*([^\n]+)') or ''
    if comments >= 15 and link and status:match('^handmatig:') then
      table.insert(links, link)
    end
  end
  return links
end

function M.prepare(edition)
  local cmd = vim.list_extend(vim.deepcopy(command), { 'prepare', '--edition', edition })
  workflow('Meestgelezen · artikelen en cijfers ophalen…', vim.log.levels.INFO)
  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      local data = decode(result, 'Meestgelezen weekoverzicht voorbereiden mislukt.')
      if not data or type(data.document) ~= 'string' then return end
      local buf = open_editable('Meestgelezen review ' .. edition, data.document, true)
      vim.keymap.set('n', '<leader>kv', function() M.generate(buf) end, {
        buffer = buf,
        desc = '[K]rant [v]eelgelezen review verwerken',
      })
      local links = facebook_links_needing_review(data.document)
      if #links > 0 then
        local choice = require('user_dialog').confirm(
          string.format('%d artikel(en) hebben minimaal 15 reacties die handmatig moeten worden bekeken. Facebooklinks openen?', #links),
          '&Ja\n&Nee',
          1
        )
        if choice == 1 then browser.open_urls(links) end
      end
      workflow(
        'Review geopend. Kies overzicht, los of overslaan; plak zo nodig reacties en druk opnieuw <leader>kv.',
        vim.log.levels.INFO,
        { ttl = 12 }
      )
    end)
  end)
end

function M.generate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
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
      workflow(string.format('%d artikelbuffer(s) gemaakt; controleer en publiceer via de gewone flow.', opened),
        vim.log.levels.INFO, { ttl = 10 })
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
  vim.keymap.set('n', '<leader>kv', M.run, {
    desc = '[K]rant [v]eelgelezen weekoverzicht',
  })
end

M._facebook_links_needing_review = facebook_links_needing_review

return M
