local M = {}

local ARTICLE_BOUNDARY = '=== ARTIKEL ==='

local function plan_for(buf)
  local plan = vim.b[buf].gn_export
  if type(plan) ~= 'table' or type(plan.dir) ~= 'string' or type(plan.txt_name) ~= 'string' then
    return nil
  end
  return plan
end

function M.prepare(buf, options)
  buf = buf or vim.api.nvim_get_current_buf()
  options = options or {}
  if type(options.dir) ~= 'string' or options.dir == '' then return nil, 'Vormgevingsmap ontbreekt.' end
  if type(options.txt_name) ~= 'string' or options.txt_name == '' then return nil, 'Naam van vormgevingstekst ontbreekt.' end

  if vim.fn.mkdir(options.dir, 'p') == 0 and vim.fn.isdirectory(options.dir) ~= 1 then
    return nil, 'Vormgevingsmap kon niet worden gemaakt: ' .. options.dir
  end

  if options.photo_src or options.img_name then
    if type(options.photo_src) ~= 'string' or options.photo_src == '' then return nil, 'Bronfoto ontbreekt.' end
    if type(options.img_name) ~= 'string' or options.img_name == '' then return nil, 'Naam van vormgevingsfoto ontbreekt.' end
    local destination = options.dir .. '/' .. options.img_name
    local ok, error_message = vim.uv.fs_copyfile(options.photo_src, destination)
    if not ok then
      return nil, 'Foto kopiëren naar vormgeving mislukt: ' .. (error_message or destination)
    end
  end

  local plan = {
    dir = options.dir,
    txt_name = options.txt_name,
    img_name = options.img_name,
    label = options.label,
  }
  vim.b[buf].gn_export = plan
  return plan
end

function M.pending(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  return plan_for(buf)
end

function M.placeholders(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local found, seen = {}, {}
  local in_article = false
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      in_article = true
    elseif in_article then
      for placeholder in line:gmatch('{{.-}}') do
        if not seen[placeholder] then
          seen[placeholder] = true
          table.insert(found, placeholder)
        end
      end
    end
  end
  return found
end

function M.validate(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local placeholders = M.placeholders(buf)
  if #placeholders == 0 then return true end
  return false, 'Vul eerst de templatevelden in: ' .. table.concat(placeholders, ', ')
end

local function export_content(buf)
  local export_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local fm_caption, fm_credit
  if export_lines[1] == '---' then
    local in_media = false
    for i = 2, #export_lines do
      if export_lines[i] == '---' then break end
      if export_lines[i]:match('^media:') then
        in_media = true
      elseif in_media and export_lines[i]:match('^%S') then
        in_media = false
      elseif in_media then
        local value = export_lines[i]:match('^%s+caption:%s*"?(.-)"?%s*$')
        if value and value ~= 'null' and value ~= '' then fm_caption = value end
        value = export_lines[i]:match('^%s+credit:%s*"?(.-)"?%s*$')
        if value and value ~= 'null' and value ~= '' then fm_credit = value end
      end
    end
  end

  if export_lines[1] == '---' then
    for i = 2, #export_lines do
      if export_lines[i] == '---' then
        local stripped = {}
        for j = i + 1, #export_lines do table.insert(stripped, export_lines[j]) end
        export_lines = stripped
        break
      end
    end
  end

  for i, line in ipairs(export_lines) do
    if vim.trim(line) == ARTICLE_BOUNDARY then
      local article_only = {}
      for j = i + 1, #export_lines do table.insert(article_only, export_lines[j]) end
      export_lines = article_only
      break
    end
  end

  local streamer_text
  local body = {}
  local skip_next_streamer = false
  for _, line in ipairs(export_lines) do
    local trimmed = vim.trim(line)
    local streamer = trimmed:match('^[Ss]treamer:%s*(.+)$')
    if streamer then
      streamer_text = streamer
    elseif trimmed:match('^Eindredactie:%s*') then
      -- Alleen workflowmetadata; niet exporteren.
    elseif trimmed == '***' then
      skip_next_streamer = true
    elseif skip_next_streamer then
      if trimmed ~= '' then skip_next_streamer = false end
    elseif trimmed:match('^>%s') or trimmed == '>' then
      local quote = trimmed:match('^>%s*(.+)$')
      if quote and not streamer_text then streamer_text = quote end
    else
      table.insert(body, line)
    end
  end

  local header = {}
  if streamer_text then table.insert(header, 'Streamer: ' .. streamer_text) end
  if fm_caption then table.insert(header, 'Bijschrift: ' .. fm_caption) end
  if fm_credit then
    local credit_name = fm_credit:gsub('^[Ff]oto:%s*', '')
    table.insert(header, 'Fotograaf: ' .. credit_name)
  end

  while #body > 0 and vim.trim(body[1]) == '' do table.remove(body, 1) end
  while #body > 0 and vim.trim(body[#body]) == '' do table.remove(body) end

  local final = {}
  for _, line in ipairs(header) do table.insert(final, line) end
  if #header > 0 then table.insert(final, '') end
  for _, line in ipairs(body) do table.insert(final, line) end
  return final
end

function M.finalize(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local plan = plan_for(buf)
  if not plan then return nil end

  local valid, validation_error = M.validate(buf)
  if not valid then return nil, validation_error end
  if vim.fn.mkdir(plan.dir, 'p') == 0 and vim.fn.isdirectory(plan.dir) ~= 1 then
    return nil, 'Vormgevingsmap kon niet worden gemaakt: ' .. plan.dir
  end

  local path = plan.dir .. '/' .. plan.txt_name
  if vim.fn.writefile(export_content(buf), path) ~= 0 then
    return nil, 'Vormgevingstekst kon niet worden geschreven: ' .. path
  end
  vim.b[buf].gn_export = nil
  return path
end

return M
