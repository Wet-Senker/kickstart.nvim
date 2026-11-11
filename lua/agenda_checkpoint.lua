-- Opaque transport; Python owns freshness, scope and event equality.
local M = {}

function M.remember(buf, data)
  if not data or type(data.checkpoint) ~= 'table' or not vim.api.nvim_buf_is_valid(buf) then return end
  local line = 'agenda_duplicate_check: ' .. vim.json.encode(data.checkpoint)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if lines[1] == '---' then
    for i = 2, #lines do
      if lines[i]:match('^agenda_duplicate_check:') then
        local last = i
        while last < #lines and (lines[last + 1]:match('^%s') or lines[last + 1] == '') do last = last + 1 end
        local ok, previous = pcall(vim.json.decode, lines[i]:match('^agenda_duplicate_check: (.*)$') or '')
        local previous_time = ok and type(previous) == 'table' and previous.checked_at or nil
        if not ok then
          -- A shared Python action may have rendered the opaque object as YAML.
          -- Replace that entire owned block, retaining adjacent metadata/body.
          for j = i + 1, last do
            previous_time = tonumber(lines[j]:match('^  checked_at:%s*([%d.eE+-]+)%s*$')) or previous_time
          end
        end
        if type(previous_time) == 'number' and type(data.checkpoint.checked_at) == 'number'
            and previous_time > data.checkpoint.checked_at then return end
        if not ok or not vim.deep_equal(previous, data.checkpoint) then
          vim.api.nvim_buf_set_lines(buf, i - 1, last, false, { line })
        end
        return
      end
      if lines[i] == '---' then vim.api.nvim_buf_set_lines(buf, i - 1, i - 1, false, { line }); return end
    end
  else
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '---', line, '---', '' })
  end
end

return M
