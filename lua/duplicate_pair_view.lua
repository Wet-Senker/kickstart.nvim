-- Small UI adapter: only the selected group reaches the browser.
local M = {}
local browser = require 'ordered_browser'

function M.open(pair, group)
  local urls = {}
  local candidates = group and group.open_urls
  if type(candidates) ~= 'table' then
    candidates = {}
    for _, side in ipairs { pair.left or {}, pair.right or {} } do
      if type(side.editor_url) == 'string' then candidates[#candidates + 1] = side.editor_url end
    end
  end
  for _, url in ipairs(candidates) do
    if type(url) == 'string' and url ~= '' and not vim.tbl_contains(urls, url) then
      urls[#urls + 1] = url
    end
  end
  if #urls > 0 then browser.open_urls(urls) end
end

return M
