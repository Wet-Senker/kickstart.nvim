-- Snelle, volledig deterministische herkenning van geplakte artikelen.
--
-- Deze module doet uitsluitend lokale string- en patrooncontroles. Acties
-- (templates, menu's, AI-metadata) horen bewust bij de aanroepende workflow.

local M = {}

M.CALENDAR_THRESHOLD = 8
M.EMERGENCY_THRESHOLD = 6
M.RUBRIC_PROMPT_THRESHOLD = 70
M.RUBRIC_AUTO_THRESHOLD = 100

local MONTHS = {
  januari = 1,
  februari = 2,
  maart = 3,
  april = 4,
  mei = 5,
  juni = 6,
  juli = 7,
  augustus = 8,
  september = 9,
  oktober = 10,
  november = 11,
  december = 12,
}

local function add_evidence(evidence, value)
  for _, existing in ipairs(evidence) do
    if existing == value then return end
  end
  table.insert(evidence, value)
end

local function threshold_confidence(points, threshold)
  if points <= 0 then return 0 end
  return math.min(100, math.floor((points * 70 / threshold) + 0.5))
end

local function result(fields)
  fields.evidence = fields.evidence or {}
  fields.points = fields.points or 0
  fields.confidence = fields.confidence or 0
  return fields
end

-- Tel afzonderlijke kalenderdatums zonder dezelfde datum dubbel te tellen als
-- die zowel in een kop als in de body terugkomt. Dit blijft bewust een snelle
-- lokale veiligheidscheck: Nederlandse maanddatums en gangbare numerieke
-- datums zijn voldoende voor de importwaarschuwing.
function M.calendar_date_count(text)
  local t = type(text) == 'string' and text:lower() or ''
  local seen = {}

  local function add_date(day, month)
    day, month = tonumber(day), tonumber(month)
    if day and month and day >= 1 and day <= 31 and month >= 1 and month <= 12 then
      seen[('%02d-%02d'):format(month, day)] = true
    end
  end

  for month_name, month_number in pairs(MONTHS) do
    local pattern = '%f[%d](%d%d?)%s+' .. month_name .. '%f[%A]'
    for day in t:gmatch(pattern) do
      add_date(day, month_number)
    end
  end

  for _, pattern in ipairs({
    '%f[%d]%d%d%d%d[-/](%d%d?)[-/](%d%d?)%f[%D]',
    '%f[%d](%d%d?)[-/.](%d%d?)[-/.]%d%d%d%d%f[%D]',
  }) do
    for first, second in t:gmatch(pattern) do
      if pattern:find('^%%f%[%%d%]%%d%%d%%d%%d') then
        add_date(second, first)
      else
        add_date(first, second)
      end
    end
  end

  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  return count
end

local function calendar_detection(text)
  local t = text:lower()
  local score = 0
  local evidence = {}

  for _, phrase in ipairs({
    'op het programma', 'staat op het programma',
    'vindt plaats', 'wordt gehouden', 'begint om', 'start om', 'eindigt om',
    'de deuren gaan open', 'de zaal gaat open',
    'inloop vanaf', 'verzamelen om', 'vertrek om',
    'aansluitend is er', 'na afloop',
    'opgeven kan', 'reserveren via',
    'kaarten via', 'kaarten verkrijgbaar', 'tickets zijn verkrijgbaar',
    'de entree bedraagt', 'toegang bedraagt', 'deelname kost',
    'beperkt aantal plaatsen', 'vol is vol',
    'voor alle leeftijden', 'jong en oud',
    'vrije inloop', 'zonder aanmelding',
    'kijk voor meer informatie',
    'iedereen kan deelnemen', 'iedereen kan binnenlopen',
    'onder begeleiding van',
  }) do
    if t:find(phrase, 1, true) then
      score = score + 3
      add_evidence(evidence, 'evenementfrase: ' .. phrase)
    end
  end

  if t:find('om%s+%d%d?[%.:]%d%d') or t:find('%d%d?[%.:]%d%d%s*uur') then
    score = score + 3
    add_evidence(evidence, 'kloktijd')
  end
  if t:find('van%s+%d%d?[%.:]%d%d%s+tot') then
    score = score + 3
    add_evidence(evidence, 'tijdvenster')
  end
  if t:find('vanaf%s+%d%d?[%.:]%d%d') then
    score = score + 2
    add_evidence(evidence, 'begintijd')
  end
  if t:find('aanvang%s+%d%d?') then
    score = score + 2
    add_evidence(evidence, 'aanvang')
  end

  for _, day in ipairs({
    'maandag', 'dinsdag', 'woensdag', 'donderdag',
    'vrijdag', 'zaterdag', 'zondag',
  }) do
    if t:find(day .. '%s+%d') then
      score = score + 2
      add_evidence(evidence, 'weekdag met datum')
      break
    end
  end

  if t:find('elke%s+%a') or t:find('iedere%s+%a')
      or t:find('wekelijks%s+op') or t:find('maandelijks%s+op') then
    score = score + 2
    add_evidence(evidence, 'herhalend tijdspatroon')
  end

  if t:find('van%s+%d%d?%s+%a+%s+tot%s+en%s+met') then
    score = score + 2
    add_evidence(evidence, 'datumbereik')
  end
  if t:find('%d%d?%s+%a+%s+%d%d%d%d') then
    score = score + 2
    add_evidence(evidence, 'volledige datum')
  end

  local has_complex_date_range =
    t:find('van%s+%a+%s+%d%d?%s+%a+%s+tot%s+en%s+met%s+%a+%s+%d%d?') ~= nil
    or t:find('van%s+%d%d?%s+%a+%s+tot%s+en%s+met%s+%d%d?') ~= nil
    or t:find('van%s+%d%d?%s+tot%s+en%s+met%s+%d%d?%s+%a+') ~= nil

  local access = 0
  for _, word in ipairs({
    'aanmelden', 'inschrijven', 'reserveren', 'kaartjes', 'tickets',
    'gratis', 'entree', 'kosten', 'deelname', 'opgeven',
    'voorverkoop', 'aanmelding', 'inschrijving', 'reservering',
  }) do
    if t:find(word) and access < 4 then
      access = access + 1
      add_evidence(evidence, 'deelname/toegang')
    end
  end
  score = score + access

  local activity_count = 0
  for _, word in ipairs({
    'concert', 'lezing', 'workshop', 'tentoonstelling', 'expositie',
    'bijeenkomst', 'evenement', 'festival', 'excursie', 'wandeling',
    'cursus', 'training', 'presentatie', 'optreden', 'uitvoering',
    'voorstelling', 'theater', 'markt', 'toernooi', 'samenzang',
    'kerkdienst', 'filmavond', 'informatieavond', 'proeverij',
    'benefiet', 'jubileum', 'herdenking', 'clinic', 'rondleiding',
    'speurtocht', 'fietstocht', 'rondvaart', 'repetitie', 'open dag',
    'kunstweekend',
  }) do
    if t:find(word) then
      activity_count = activity_count + 1
      add_evidence(evidence, 'activiteitstype: ' .. word)
    end
  end
  if has_complex_date_range and activity_count > 0 then
    score = score + 3
    add_evidence(evidence, 'meerdaags evenement')
  end
  score = score + math.min(3, math.floor(activity_count / 2))

  local explicitly_not_public = t:find('niet toegankelijk voor publiek', 1, true)
    or t:find('besloten bijeenkomst', 1, true)
    or t:find('besloten vergadering', 1, true)
  local has_audience_signal = not explicitly_not_public and (
    t:find('bezoeker') ~= nil
    or t:find('deelnemer') ~= nil
    or t:find('belangstellend') ~= nil
    or t:find('publiek') ~= nil
    or t:find('iedereen kan', 1, true) ~= nil
  )
  if activity_count == 0 and access == 0 and not has_audience_signal then
    score = math.min(score, M.CALENDAR_THRESHOLD - 1)
  end

  return result({
    id = 'calendar',
    label = 'Kalender',
    category = 'workflow',
    policy = 'metadata',
    points = score,
    confidence = threshold_confidence(score, M.CALENDAR_THRESHOLD),
    evidence = evidence,
  })
end

local function emergency_detection(text)
  local t = text:lower()
  local score = 0
  local evidence = {}

  for _, phrase in ipairs({
    'politie', 'brandweer', 'ambulance', 'traumahelikopter',
    '112', 'reanimatie', 'gereanimeerd',
    'spoedeisende', 'spoedhulp',
    'hulpdiensten ter plaatse', 'hulpverleners',
  }) do
    if t:find(phrase, 1, true) then
      score = score + 3
      add_evidence(evidence, 'hulpdienst: ' .. phrase)
    end
  end

  for _, phrase in ipairs({
    'brand', 'brandstichting', 'explosie', 'gaslek', 'ongeluk', 'aanrijding',
    'botsing', 'kop-staart', 'frontale botsing', 'ravage', 'zwaargewond',
    'lichtgewond', 'slachtoffer', 'omgekomen', 'gewonden', 'levensgevaar',
    'kritieke toestand', 'ziekenhuis overgebracht', 'overgebracht naar',
    'ingerekend', 'aangehouden', 'verdachte', 'vuurwerk', 'schietpartij',
    'steekpartij', 'mishandeling', 'beroving', 'overval',
    'vermiste', 'vermist', 'waterongeval', 'verdrinking',
    'medische noodsituatie', 'reanimatie', 'hartaanval',
    'bewusteloos', 'bewusteloze',
  }) do
    if t:find(phrase, 1, true) then
      score = score + 2
      add_evidence(evidence, 'incident: ' .. phrase)
    end
  end

  if t:find('ter hoogte van') or t:find('op de hoek van') or t:find('nabij de') then
    score = score + 1
    add_evidence(evidence, 'precieze locatie')
  end
  if t:find('%d%d?[%.:]%d%d%s*uur') or t:find('om%s+%d%d?[%.:]%d%d') then
    score = score + 1
    add_evidence(evidence, 'precieze tijd')
  end
  if t:find('politie kampen') or t:find('ijsselland') or t:find('veiligheidsregio') then
    score = score + 1
    add_evidence(evidence, 'hulpdienstbron')
  end

  return result({
    id = '112',
    label = '112-bericht',
    category = 'rubric',
    policy = 'confirm',
    points = score,
    confidence = threshold_confidence(score, M.EMERGENCY_THRESHOLD),
    evidence = evidence,
  })
end

local function numbered_marker_position(text, number)
  local prefix = '%f[%d]' .. tostring(number)
  local parenthesized = text:find(prefix .. '%)%.?%s*')
  local dotted = text:find(prefix .. '%.%s+')
  if parenthesized and dotted then return math.min(parenthesized, dotted) end
  return parenthesized or dotted
end

local function kamper_kiek_detection(text)
  local t = text:lower()
  local evidence = {}
  local confidence = 0
  local has_phrase = t:find('kamper%s+kiek') ~= nil
    or t:find('kiek%s+op%s+de%s+wîêk') ~= nil
    or t:find('kiek%s+op%s+de%s+wiek') ~= nil

  local fixed_intro = 'in de brug kijkt burgemeester sander de rouwe wekelijks in fotovorm terug op de afgelopen week.'
  local already_applied = has_phrase and t:find(fixed_intro, 1, true) ~= nil
  if already_applied then
    return result({
      id = 'kamper_kiek',
      label = 'Kamper Kiek',
      category = 'rubric',
      policy = 'auto',
      state = 'already_applied',
      evidence = { 'vaste Kamper-Kiekintro staat al in het artikel' },
    })
  end

  if has_phrase then
    confidence = 70
    add_evidence(evidence, 'vaste tekst “Kamper Kiek”')
  end

  local first = numbered_marker_position(t, 1)
  local second = numbered_marker_position(t, 2)
  local third = numbered_marker_position(t, 3)
  if first then
    confidence = confidence + 10
    add_evidence(evidence, 'nummering begint bij 1')
  end
  if first and second and second > first then
    confidence = confidence + 10
    add_evidence(evidence, 'opeenvolgend nummer 2')
  end
  if second and third and third > second then
    confidence = confidence + 10
    add_evidence(evidence, 'opeenvolgend nummer 3')
  end

  -- Een willekeurige genummerde lijst is nooit een rubrieksignaal.
  if not has_phrase then confidence = 0 end

  return result({
    id = 'kamper_kiek',
    label = 'Kamper Kiek',
    category = 'rubric',
    policy = 'auto',
    points = confidence,
    confidence = math.min(100, confidence),
    evidence = evidence,
  })
end

local function hondenhoek_detection(text)
  local t = text:lower()
  local evidence = {}
  local confidence = 0
  local has_title = t:find('%f[%a]hondenhoek%f[%A]') ~= nil
  local has_author = t:find('bert%s+nieuwenhuis') ~= nil
  local has_dog_word = t:find('%f[%a]hond%f[%A]') ~= nil
    or t:find('%f[%a]honden%f[%A]') ~= nil

  local fixed_intro = 'in de column hondenhoek belicht kynologisch gedragstherapeut en doorgewinterd hondenkenner bert nieuwenhuis'
  if t:find(fixed_intro, 1, true) then
    return result({
      id = 'hondenhoek',
      label = 'Hondenhoek',
      category = 'rubric',
      policy = 'auto',
      state = 'already_applied',
      evidence = { 'vaste Hondenhoekintro staat al in het artikel' },
    })
  end

  if has_title then
    confidence = confidence + 70
    add_evidence(evidence, 'vaste tekst “Hondenhoek”')
  end
  if has_author then
    confidence = confidence + 70
    add_evidence(evidence, 'auteur Bert Nieuwenhuis')
  end
  if has_dog_word then
    confidence = confidence + 30
    add_evidence(evidence, 'zelfstandig woord hond/honden')
  end

  return result({
    id = 'hondenhoek',
    label = 'Hondenhoek',
    category = 'rubric',
    policy = 'auto',
    points = math.min(100, confidence),
    confidence = math.min(100, confidence),
    evidence = evidence,
  })
end

local DETECTORS = {
  calendar_detection,
  emergency_detection,
  kamper_kiek_detection,
  hondenhoek_detection,
}

local function sort_by_confidence(results)
  table.sort(results, function(left, right)
    if left.confidence == right.confidence then return left.id < right.id end
    return left.confidence > right.confidence
  end)
  return results
end

function M.evaluate(text)
  text = type(text) == 'string' and text or ''
  local all, by_id, rubrics, workflows = {}, {}, {}, {}
  for _, detector in ipairs(DETECTORS) do
    local detected = detector(text)
    table.insert(all, detected)
    by_id[detected.id] = detected
    if detected.category == 'rubric' then
      table.insert(rubrics, detected)
    else
      table.insert(workflows, detected)
    end
  end
  return {
    all = all,
    by_id = by_id,
    rubrics = sort_by_confidence(rubrics),
    workflows = sort_by_confidence(workflows),
  }
end

function M.rubric_decision(evaluation)
  local candidates = {}
  for _, detected in ipairs((evaluation or {}).rubrics or {}) do
    -- Een al aanwezige vaste templatevorm is sterker bewijs dan losse
    -- signaalwoorden in de inhoud. Zo wordt een bestaande Kamper Kiek waarin
    -- politie of brandweer voorkomt niet alsnog als 112-bericht aangeboden.
    if detected.state == 'already_applied' then
      return { action = 'none', candidates = {}, existing = detected }
    end
    if detected.confidence >= M.RUBRIC_PROMPT_THRESHOLD then
      table.insert(candidates, detected)
    end
  end
  sort_by_confidence(candidates)
  if #candidates == 0 then return { action = 'none', candidates = {} } end

  local top = candidates[1]
  if #candidates == 1
      and top.policy == 'auto'
      and top.confidence >= M.RUBRIC_AUTO_THRESHOLD then
    return { action = 'auto', candidate = top, candidates = candidates }
  end
  return { action = 'confirm', candidate = top, candidates = candidates }
end

function M.calendar_signal_score(text)
  return calendar_detection(text).points
end

function M.emergency_signal_score(text)
  return emergency_detection(text).points
end

return M
