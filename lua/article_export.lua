-- Dunne client voor de gedeelde, opgeschoonde artikeluitvoer in Python.
local M = {}
local notifications = require('texttools_notify')
local commands = require('texttools_commands')

local function clean_article(buf, done)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local source = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  if vim.trim(source) == '' then
    notifications.notify('Buffer is leeg.', vim.log.levels.WARN)
    return
  end
  notifications.system(
    { commands.bin('python'), '-m', 'texttools.article_export_cli' },
    { stdin = source, text = true },
    notifications.schedule_wrap(function(result)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
        notifications.notify(
          'Artikel gewijzigd tijdens de export; start de klembordactie opnieuw.',
          vim.log.levels.WARN
        )
        return
      end
      local ok, payload = pcall(vim.json.decode, result.stdout or '')
      if result.code ~= 0 or not ok or type(payload) ~= 'table'
          or payload.schema_version ~= 1 or type(payload.markdown) ~= 'string'
      then
        local message = vim.trim(result.stderr or '')
        notifications.notify(
          'Artikeluitvoer mislukt: ' .. (message ~= '' and message or 'ongeldig resultaat'),
          vim.log.levels.ERROR
        )
        return
      end
      done(payload.markdown)
    end)
  )
end

function M.copy_markdown(buf)
  clean_article(buf, function(markdown)
    vim.fn.setreg('+', markdown)
    notifications.workflow('Schone artikel-Markdown staat op het klembord.')
  end)
end

function M.copy_rich_text(buf)
  clean_article(buf, function(markdown)
    notifications.system(
      {
        '/bin/zsh', '-o', 'pipefail', '-c',
        'LC_CTYPE=UTF-8 pandoc -f markdown-smart -t html --ascii'
          .. ' | /usr/bin/textutil -stdin -stdout -format html -convert rtf -encoding UTF-8'
          .. ' | /usr/bin/pbcopy -Prefer rtf',
      },
      { stdin = markdown, text = true },
      notifications.schedule_wrap(function(result)
        if result.code ~= 0 then
          local message = vim.trim(result.stderr or '')
          notifications.notify(
            'Rich-textklembord mislukt: ' .. (message ~= '' and message or 'onbekende fout'),
            vim.log.levels.ERROR
          )
          return
        end
        notifications.workflow('Schone rich text staat op het klembord.')
      end)
    )
  end)
end

return M
