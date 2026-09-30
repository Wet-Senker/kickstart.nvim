-- Lokaliseren (geen AI): edition-localize wordt per krant aangeroepen met de
-- bronbody als stdin; de verzamelde varianten gaan naar de apply-stap. De
-- apply-stap zelf (die Python draait en UI opent) wordt gestubt.
local ai = require("ai_text")

local applied
ai._apply_edition_versions = function(_buf, codes, names, variants, source, done)
  applied = { codes = codes, names = names, variants = variants, source = source }
  done(true)
  return true
end

local calls = {}
local original_system = vim.system
vim.system = function(cmd, opts, cb)
  table.insert(calls, { cmd = cmd, stdin = opts and opts.stdin })
  cb({ code = 0, stdout = "LOKAAL(" .. tostring(cmd[3]) .. ")\n" })
  return {}
end

local buf = vim.api.nvim_create_buf(false, true)
local source = "Kop\n\nZeewolde Actueel. redactie@zeewolde-actueel.nl"
ai._localize_edition_versions(buf, source, { "B", "SW" }, { "De Brug", "De Swollenaer" })

assert(vim.wait(1000, function() return applied ~= nil end, 10), "apply werd niet aangeroepen")
vim.system = original_system

assert(#calls == 2, "edition-localize niet één keer per krant aangeroepen")
for _, call in ipairs(calls) do
  assert(call.cmd[1]:find("edition-localize", 1, true), "verkeerde binary")
  assert(call.cmd[2] == "--edition", "verkeerde vlag")
  assert(call.stdin == source, "bronbody niet als stdin meegegeven")
end
assert(applied.variants.B == "LOKAAL(B)", "B-variant niet verzameld")
assert(applied.variants.SW == "LOKAAL(SW)", "SW-variant niet verzameld")
assert(applied.source == source, "bron niet doorgegeven aan apply")
assert(applied.codes[1] == "B" and applied.codes[2] == "SW", "codes niet doorgegeven")

-- Bij een fout in één editie komt er geen half resultaat: apply mag niet draaien.
applied = nil
calls = {}
vim.system = function(cmd, opts, cb)
  local code = tostring(cmd[3])
  if code == "SW" then
    cb({ code = 1, stdout = "", stderr = "kapot" })
  else
    cb({ code = 0, stdout = "LOKAAL(" .. code .. ")\n" })
  end
  return {}
end
ai._apply_edition_versions = function() error("apply mocht niet draaien bij een fout") end
ai._localize_edition_versions(buf, source, { "B", "SW" }, { "De Brug", "De Swollenaer" })
local drained = false
vim.schedule(function() drained = true end)
assert(vim.wait(1000, function() return drained end, 10))
assert(applied == nil, "apply draaide ondanks een mislukte editie")
vim.system = original_system

print("localize: OK")
