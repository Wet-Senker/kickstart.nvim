-- Alleen kalenderpresentatie. Suggesties en domeinregels komen uit Python.
local M = {}
local names = { 'zo', 'ma', 'di', 'wo', 'do', 'vr', 'za' }

function M.days(offset, today)
  local y, m, d = (today or os.date('%Y-%m-%d')):match('^(%d+)-(%d+)-(%d+)$')
  assert(y, 'Kalender verwacht YYYY-MM-DD')
  local days = {}
  for index = 0, 6 do
    -- Kalenderdagen, geen blokken van 86400 seconden (zomer-/wintertijd).
    local stamp = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) + offset * 7 + index, hour = 12 })
    days[#days + 1] = { date = os.date('%Y-%m-%d', stamp), weekday = names[tonumber(os.date('%w', stamp)) + 1], stamp = stamp }
  end
  return days
end

function M.choose(opts, done)
  local function show(offset)
    local items, selected = {}, 1
    for _, day in ipairs(M.days(offset, opts.today)) do
      local recommended = day.date == opts.suggested
      items[#items + 1] = { value = day.date, label = day.date .. '  ' .. day.weekday .. (recommended and ' ← voorgesteld' or '') }
      if recommended then selected = #items end
    end
    if offset > 0 then items[#items + 1] = { value = 'prev', label = '← Vorige week' } end
    items[#items + 1] = { value = 'next', label = '→ Volgende week' }
    if opts.indefinite then items[#items + 1] = { value = 'indefinite', label = 'Voor onbepaalde tijd' } end
    require('user_dialog').select(items, {
      prompt = opts.prompt or 'Kies een datum:', native = true, default = selected,
      format_item = function(item) return item.label end,
    }, function(item)
      if not item then done(nil)
      elseif item.value == 'prev' then show(offset - 1)
      elseif item.value == 'next' then show(offset + 1)
      else done(item.value) end
    end)
  end
  show(opts.offset or 0)
end

return M
