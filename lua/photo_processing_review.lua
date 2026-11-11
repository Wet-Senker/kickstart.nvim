-- Optional crop recovery. Domain action and wording come from Python.
local M = {}

function M.offer(status)
  if type(status) == 'table' and type(status.recovery) == 'table'
      and status.recovery.action == 'use_standard_photo_processing' then return status.recovery end
  for _, phase in ipairs(type(status) == 'table' and status.phases or {}) do
    local offer = phase.recovery
    if phase.name == 'media' and phase.status == 'failed' and type(offer) == 'table'
        and offer.action == 'use_standard_photo_processing' then return offer end
  end
end

function M.review(buf, offer, done)
  require('user_dialog').select({
    'Doorgaan met Pubbles standaarduitsnede (deze verzending)',
    'Stoppen; later opnieuw proberen',
  }, {
    source_buf = buf, native = true,
    prompt = offer.title .. '\n' .. offer.message,
  }, function(_, index) done(index == 1) end)
end

return M
