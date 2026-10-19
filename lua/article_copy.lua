-- Dunne client: Python bepaalt welke artikelinhoud in een schone kopie hoort.
local M = {}
local notifications = require('texttools_notify')
local commands = require('texttools_commands')
local paths = require('texttools_paths')
local requests = {}

function M.copy(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local request = {}
  requests[buf] = request
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  local source_name = vim.api.nvim_buf_get_name(buf)
  local directory = paths.work()
  if source_name ~= '' and vim.bo[buf].buftype == '' then
    directory = vim.fs.dirname(source_name)
  end
  local stem = source_name ~= '' and vim.fn.fnamemodify(source_name, ':t:r') or 'artikel'
  stem = stem:gsub('[^%w_.-]', '-')
  local started, err = pcall(notifications.system,
    { commands.bin('python'), '-m', 'texttools.article_copy_cli' },
    { text = true, stdin = text, timeout = 10000 },
    notifications.schedule_wrap(function(result)
      if requests[buf] ~= request then return end
      requests[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        notifications.notify('Artikel gewijzigd tijdens kopiëren; maak de kopie opnieuw.', vim.log.levels.WARN)
        return
      end
      local ok, data = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(data) ~= 'table'
          or data.contract_version ~= 1 or type(data.markdown) ~= 'string'
          or data.markdown == '' then
        notifications.notify('Artikelkopie mislukt: ' .. vim.trim(result.stderr or ''), vim.log.levels.ERROR)
        return
      end
      local copied = vim.api.nvim_create_buf(true, false)
      local suffix = copied
      local name
      repeat
        name = vim.fs.joinpath(directory, 'Kopie-' .. stem .. '-' .. suffix .. '.md')
        suffix = suffix + 1
      until vim.fn.filereadable(name) == 0 and vim.fn.bufnr(name) == -1
      vim.api.nvim_buf_set_name(copied, name)
      vim.bo[copied].bufhidden = 'hide'
      vim.bo[copied].swapfile = false
      local content = data.markdown:gsub('\n$', '')
      vim.api.nvim_buf_set_lines(copied, 0, -1, false, vim.split(content, '\n', { plain = true }))
      vim.bo[copied].filetype = 'markdown'
      vim.bo[copied].modified = true
      vim.api.nvim_set_current_buf(copied)
      vim.api.nvim_win_set_cursor(0, { 1, 3 })
      notifications.notify('Schone kopie geopend. Vul e: in, kies opnieuw een foto en herschrijf met <leader>ar.', vim.log.levels.INFO)
    end))
  if not started then
    if requests[buf] == request then requests[buf] = nil end
    notifications.notify('Artikelkopie kon niet starten: ' .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('ArtikelKopie', function() M.copy() end, {
    desc = 'Schone artikelkopie voor een andere krant', force = true,
  })
  vim.keymap.set('n', '<leader>aK', function() M.copy() end, {
    desc = 'Schone artikelkopie voor een andere krant',
  })
  return M
end

return M
