-- Presentation only: Python supplies editions, dates and allowed actions.
-- Stage the entire round locally; consumers apply nothing until done(choices).
local M = {}

function M.collect(plan, opts, done)
  if type(plan) ~= 'table' or plan.contract_version ~= 1 or type(plan.items) ~= 'table' then
    done(nil, 'Onbekend krantkeuzeplan; werk Texttools en Neovim samen bij.')
    return
  end
  local items, staged, index = plan.items, {}, 1
  local finished = false
  local function finish(choices, err)
    if finished then return end
    finished = true
    done(choices, err)
  end
  local function show()
    if opts.valid and not opts.valid() then
      finish(nil, 'Artikel gewijzigd tijdens de krantkeuzes; start opnieuw.')
      return
    end
    if index > #items then finish(staged); return end
    local item = items[index]
    local labels, actions, shortcuts = {}, {}, {}
    local keys = { website = 'w', rewrite = 'h', use_web = 'b' }
    for _, choice in ipairs(item.choices or {}) do
      local key = keys[choice.id]
      if not key or type(choice.label) ~= 'string' then
        finish(nil, 'Onbekende krantkeuze; werk Texttools en Neovim samen bij.')
        return
      end
      labels[#labels + 1] = choice.label .. ' [' .. key .. ']'
      actions[#actions + 1] = choice.id
      shortcuts[key], shortcuts[key:upper()] = #labels, #labels
    end
    if #labels == 0 or type(item.edition) ~= 'string' then
      finish(nil, 'Onvolledig krantkeuzeplan; start opnieuw.')
      return
    end
    if index > 1 then
      labels[#labels + 1], actions[#actions + 1] = 'Terug [t]', 'back'
      shortcuts.t, shortcuts.T = #labels, #labels
    end
    labels[#labels + 1], actions[#actions + 1] = 'Hele keuzeronde annuleren [a]', 'cancel'
    shortcuts.a, shortcuts.A = #labels, #labels
    local issue = type(item.newspaper_date) == 'string'
      and item.newspaper_date:gsub('^(%d%d%d%d)%-(%d%d)%-(%d%d)$', '%3-%2-%1') or 'onbekend'
    local prompt = tostring(item.publication_name or item.edition) .. ' — krant van ' .. issue
      .. ' — ' .. index .. ' van ' .. #items .. '\n\n' .. tostring(item.reason or '')
      .. '\n\nEerst alle keuzes; daarna pas uitvoeren.'
    require('user_dialog').select(labels, {
      prompt = prompt, native = true, source_buf = opts.buf, shortcuts = shortcuts,
      default = staged[item.edition] and (function()
        for i, action in ipairs(actions) do if action == staged[item.edition] then return i end end
      end)() or 1,
    }, function(_, selected)
      if finished then return end
      if opts.valid and not opts.valid() then
        finish(nil, 'Artikel gewijzigd tijdens de krantkeuzes; start opnieuw.')
        return
      end
      local action = selected and actions[selected] or 'cancel'
      if action == 'cancel' then finish(nil); return end
      if action == 'back' then index = index - 1
      else staged[item.edition], index = action, index + 1 end
      show()
    end)
  end
  show()
end

return M
