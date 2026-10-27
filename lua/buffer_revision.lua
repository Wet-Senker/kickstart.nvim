-- Clientrevisies: alle bron-/workflowvelden tellen mee, alleen expliciete
-- Tijd-/oude Melding:-regels en witruimte in het zichtbare kopblok zijn presentatieruis.
-- YAML en artikel-/staartwitruimte blijven deel van de bronrevisie.
local M = {}
local notices = require('article_notices')

function M.capture(buf)
  return {
    tick = vim.api.nvim_buf_get_changedtick(buf),
    lines = notices.content_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false)),
  }
end

function M.matches(buf, revision)
  if not vim.api.nvim_buf_is_valid(buf) then return false end
  if type(revision) == 'number' then return vim.api.nvim_buf_get_changedtick(buf) == revision end
  if type(revision) ~= 'table' then return false end
  if vim.api.nvim_buf_get_changedtick(buf) == revision.tick then return true end
  return vim.deep_equal(M.capture(buf).lines, revision.lines)
end

-- Alleen een expliciete systeemtransitie van precies onze bron mag de
-- verwachting opschuiven. Eerdere echte bewerkingen blijven een conflict.
function M.advance(revision, transition)
  if transition and vim.deep_equal(revision.lines, transition.before.lines) then
    return transition.after
  end
  return revision
end

return M
