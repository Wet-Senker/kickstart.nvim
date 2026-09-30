-- Editielijst uit één bron: Python's PUBLICATIONS (via `pubble-publications`).
--
-- NeoVim had de krantlijst (code + naam) op vijf plekken hardgecodeerd. Die
-- kopieën konden uit elkaar lopen met Python. Deze adapter haalt de lijst één
-- keer per sessie op en cachet die, zodat er nog maar één bron van waarheid is.
-- Kosten: precies één subprocess bij het eerste gebruik; daarna niets meer.

local texttools_commands = require('texttools_commands')

local M = {}
local cache = nil

local function fetch()
  local output = vim.fn.system({ texttools_commands.bin('pubble-publications') })
  if vim.v.shell_error ~= 0 then
    return nil, vim.trim(output ~= '' and output or 'onbekende fout')
  end
  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or type(decoded) ~= 'table' then
    return nil, 'onleesbare editietabel'
  end
  return decoded
end

-- De volledige editietabel (code, name, label, domain, email, dateline), in de
-- volgorde van PUBLICATIONS. Leeg bij een leesfout — de aanroeper merkt dat en
-- het probleem is zichtbaar in plaats van stil met verouderde data door te gaan.
function M.list()
  if cache then return cache end
  local decoded, err = fetch()
  if not decoded then
    vim.notify(
      'Editielijst ophalen mislukt: ' .. (err or '?') .. '. Draait de texttools-venv?',
      vim.log.levels.ERROR
    )
    return {}
  end
  cache = decoded
  return cache
end

function M.by_code(code)
  for _, edition in ipairs(M.list()) do
    if edition.code == code then return edition end
  end
  return nil
end

function M.name(code)
  local edition = M.by_code(code)
  return edition and edition.name or code
end

function M.label(code)
  local edition = M.by_code(code)
  return edition and edition.label or code
end

-- Testhaak: injecteer een vaste lijst zodat de headless-suite geen subprocess
-- hoeft te draaien. `_reset()` maakt de cache leeg.
function M._set(list)
  cache = list
end

function M._reset()
  cache = nil
end

return M
