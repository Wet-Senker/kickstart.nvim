-- Alleen een Fidget-weergave van de bestaande taakregistratie, geen eigen
-- taakstate. De handles zijn vluchtige presentatiereferenties; article_activity
-- blijft de enige eigenaar van wat daadwerkelijk loopt.
local M = {}
-- Fidget beheert de vervaltijd; geen eigen timer of tweede taakregistratie.
M.done_ttl = 8
local handles = {}
local group = 'texttools_tasks'
local hidden = false
local spinner

-- Publieke Fidget-renderhook: dezelfde animatie vóór iedere actieve regel,
-- niet één groepsicoon naast slechts één taak. Alleen presentatievelden van
-- Fidgets eigen items wijzigen; geen eigen timer of vernieuwde vervaltijd.
function M.group_name(now, items)
  local frame
  for _, item in ipairs(items) do
    item.hidden = hidden
    local title = item.annote
    local previous = item.texttools_spinner_prefix
    if previous and type(title) == 'string' and title:sub(1, #previous) == previous then
      title = title:sub(#previous + 1)
    end
    item.texttools_spinner_prefix = nil
    if type(title) == 'string' then
      if not item.data and not hidden then
        spinner = spinner or require('fidget.spinner').animate('dots')
        frame = frame or (spinner(now) .. ' ')
        item.annote = frame .. title
        item.texttools_spinner_prefix = frame
      else
        item.annote = title
      end
    end
  end
  return not hidden and 'Taken' or false
end

-- Alleen Nederlandse UI-labels; de aanroeper bevestigt de werkelijke uitkomst.
local labels = {
  Herschrijven = { 'Artikel herschrijven…', 'Artikel herschreven', 'Herschrijven' },
  ['Behoudend publicatieklaar maken'] = { 'Artikel behoudend redigeren…', 'Artikel behoudend geredigeerd', 'Behoudend redigeren' },
  Tekstcheck = { 'Tekst controleren…', 'Tekst gecontroleerd', 'Tekstcontrole' },
  Kalender = { 'Kalendergegevens ophalen…', 'Kalendergegevens verwerkt', 'Kalenderanalyse' },
  Facebook = { 'Facebook-tekst maken…', 'Facebook-tekst gemaakt', 'Facebook-tekst maken' },
  LinkedIn = { 'LinkedIn-tekst maken…', 'LinkedIn-tekst gemaakt', 'LinkedIn-tekst maken' },
  Metadata = { 'Artikelgegevens ophalen…', 'Artikelgegevens bewaard', 'Artikelgegevens ophalen' },
}

function M.completed_text(action, outcome)
  local label = labels[action]
  local name = label and label[3] or action
  if outcome == 'applied' then return '✓ ' .. (label and label[2] or action) end
  if outcome == 'failed' then return '✗ ' .. name .. ' mislukt' end
  if outcome == 'cancelled' then return '– ' .. name .. ' geannuleerd' end
  if outcome == 'not_applied' then return '– ' .. name .. ' niet toegepast' end
  if outcome == 'attention' then return '! ' .. name .. ': controle nodig' end
  -- Een technische procesexit is geen gebruikersresultaat. Laat die alleen
  -- in het technische log staan, zonder generiek 'klaar' of succesvinkje.
  return nil
end

-- Iedere taakregel heeft haar eigen teken; geen dubbel groepsbolletje of
-- groepsvinkje dat ook naast mislukte resultaten terecht kan komen.
function M.icon()
  if hidden then return false end
  return ''
end

local function backend()
  local ok_progress, progress = pcall(require, 'fidget.progress')
  local ok_notification, notification = pcall(require, 'fidget.notification')
  if not ok_progress or not ok_notification then return nil, nil end
  return progress, notification
end

local function remove(handle, notification)
  if not handle then return end
  handle:finish()
  -- Verbergen voor een keuzescherm is geen zichtbare taakafronding.
  notification.remove(group, handle.token)
  -- Fidget publiceert finish() op de volgende eventloop-tick.
  vim.schedule(function() notification.remove(group, handle.token) end)
end

function M.hide()
  local _, notification = backend()
  if not notification then handles = {}; return end
  for key, reference in pairs(handles) do
    remove(reference.handle, notification)
    handles[key] = nil
  end
  -- Ook reeds afgeronde (door Fidget tijdelijk bewaarde) regels wijken
  -- voor keuzes. Alleen onze eigen groep; LSP-/andere meldingen blijven intact.
  notification.clear(group)
  if not hidden then
    hidden = true
    vim.schedule(function()
      if hidden then notification.clear(group) end
    end)
  end
end

function M.complete(key, outcome)
  local reference = handles[key]
  if not reference then return end
  local _, notification = backend()
  if not notification then handles[key] = nil; return end
  local text = outcome ~= 'silent' and M.completed_text(reference.action, outcome) or nil
  if not text then
    remove(reference.handle, notification)
  else
    reference.handle:report {
      title = (reference.prefix or '') .. text, message = '',
    }
    reference.handle:finish()
  end
  handles[key] = nil
end

function M.show(rows)
  local was_hidden = hidden
  hidden = false
  local progress, notification = backend()
  if not progress or not notification then return end
  if was_hidden and notification.poller and notification.options then
    notification.poller:start_polling(notification.options.poll_rate)
  end
  local current = {}
  for _, row in ipairs(rows) do
    current[row.key] = true
    local reference = handles[row.key]
    local action = row.action or row.text
    local title = row.text
    if row.active_text then title = row.active_text
    elseif row.action and labels[action] then
      title = (row.prefix or '') .. labels[action][1]
        .. ((row.count or 1) > 1 and (' (' .. row.count .. ')') or '')
    end
    if reference then
      if reference.handle.title ~= title then reference.handle:report { title = title } end
      reference.prefix = row.prefix
    else
      handles[row.key] = { action = action, prefix = row.prefix, handle = progress.handle.create {
        title = title,
        message = '',
        lsp_client = { name = group },
        cancellable = false,
      } }
    end
  end
  for key in pairs(handles) do
    if not current[key] then
      M.complete(key)
    end
  end
end

-- Een keuzevenster krijgt visuele voorrang, maar wist geen voortgang of
-- voltooiingen. Fidget blijft de enige eigenaar van de achtseconden-TTL.
-- Alleen de publieke renderhooks van onze eigen groep worden tijdelijk verborgen.
function M.suspend(rows)
  M.show(rows or {})
  local _, notification = backend()
  if not notification or not notification.options then
    -- Minimale/oudere backends zonder configureerbare groepen blijven veilig.
    M.hide()
    return
  end
  hidden = true
end

return M
