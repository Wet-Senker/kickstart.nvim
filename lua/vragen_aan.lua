-- Dunne client voor de rubriek '5 vragen aan'. De vragen, de kop/intro en de
-- mailtekst komen uit texttools (de `vragen-aan`-CLI); hier staat alleen de
-- bufferorkestratie en het openen van de voorgevulde mailbox.
--
-- Bufferindeling (de markers scheiden de secties zodat elke stap alleen zijn
-- eigen deel bewerkt en herhaalbaar is):
--
--   <brontekst>
--   === 5 VRAGEN AAN ===
--   <kop + intro>              (stap <leader>vi)
--   === VRAGEN (schrap wat je niet gebruikt) ===
--   1. ...                     (stap <leader>vv; Nick schrapt tot zijn keuze)
local M = {}

local commands = require 'texttools_commands'
local dialog = require 'user_dialog'
local notifications = require 'texttools_notify'
local browser = require 'ordered_browser'
local notify = notifications.workflow

local SECTION = '=== 5 VRAGEN AAN ==='
local QUESTIONS = '=== VRAGEN (schrap wat je niet gebruikt) ==='

local busy = {}

-- ---- pure bufferhelpers (headless testbaar) -----------------------------

local function is_questions_marker(line)
  return line:match('^=== VRAGEN') ~= nil
end

local function trim_trailing_blanks(list)
  local out = vim.deepcopy(list)
  while #out > 0 and out[#out]:match('^%s*$') do out[#out] = nil end
  return out
end

local function trim_leading_blanks(list)
  local start = 1
  while start <= #list and list[start]:match('^%s*$') do start = start + 1 end
  local out = {}
  for i = start, #list do out[#out + 1] = list[i] end
  return out
end

-- Splits de bufferregels in bron / introblok / vragenblok. De bron is alles
-- vóór de sectiemarker (of de hele buffer als die er nog niet staat).
function M._split(lines)
  local section_idx, questions_idx
  for i, line in ipairs(lines) do
    if not section_idx and line == SECTION then
      section_idx = i
    elseif section_idx and not questions_idx and is_questions_marker(line) then
      questions_idx = i
    end
  end
  local function slice(a, b)
    local out = {}
    for i = a, b do out[#out + 1] = lines[i] end
    return out
  end
  if not section_idx then
    return lines, {}, {}
  end
  if not questions_idx then
    return slice(1, section_idx - 1), slice(section_idx + 1, #lines), {}
  end
  return slice(1, section_idx - 1),
    slice(section_idx + 1, questions_idx - 1),
    slice(questions_idx + 1, #lines)
end

-- Bouw de volledige buffer opnieuw op uit de drie secties.
function M._compose(source, intro, questions)
  local out = trim_trailing_blanks(source)
  out[#out + 1] = ''
  out[#out + 1] = SECTION
  for _, line in ipairs(trim_trailing_blanks(trim_leading_blanks(intro))) do out[#out + 1] = line end
  out[#out + 1] = ''
  out[#out + 1] = QUESTIONS
  for _, line in ipairs(questions) do out[#out + 1] = line end
  return out
end

local function number_questions(questions)
  local out = {}
  for i, q in ipairs(questions) do out[#out + 1] = string.format('%d. %s', i, q) end
  return out
end

function M._apply_questions(lines, questions)
  local source, intro = M._split(lines)
  return M._compose(source, intro, number_questions(questions))
end

function M._apply_intro(lines, headline, intro_text)
  local source, _, questions = M._split(lines)
  local intro = { headline }
  if intro_text ~= '' then
    intro[#intro + 1] = ''
    for _, line in ipairs(vim.split(intro_text, '\n', { plain = true })) do intro[#intro + 1] = line end
  end
  return M._compose(source, intro, questions)
end

-- De (door Nick teruggebrachte) vragen uit het vragenblok, nummer/bullet eraf.
function M._read_questions(lines)
  local _, _, questions = M._split(lines)
  local out = {}
  for _, line in ipairs(questions) do
    local text = line:gsub('^%s*%d+[.)]%s*', ''):gsub('^%s*[-*•]%s*', '')
    if text:match('%S') then out[#out + 1] = vim.trim(text) end
  end
  return out
end

function M._source_text(lines)
  local source = M._split(lines)
  return table.concat(trim_trailing_blanks(source), '\n')
end

local function percent_encode(value)
  return (value:gsub('[^%w%-_%.~]', function(c) return string.format('%%%02X', string.byte(c)) end))
end

function M._mailto(recipient, subject, body)
  return 'mailto:' .. recipient
    .. '?subject=' .. percent_encode(subject)
    .. '&body=' .. percent_encode(body)
end

-- ---- commando's ---------------------------------------------------------

local function run_cli(buf, args, stdin, title, on_json)
  if busy[buf] then
    notify('Er loopt al een 5-vragen-actie in deze buffer.', vim.log.levels.INFO)
    return
  end
  busy[buf] = true
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cmd = { commands.bin('python'), '-m', 'texttools.vragen_aan_cli' }
  vim.list_extend(cmd, args)
  notifications.system(cmd, { text = true, stdin = stdin, timeout = 90000 }, function(result)
    notifications.schedule(function()
      busy[buf] = nil
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if result.code ~= 0 then
        notify('5 vragen aan — ' .. title .. ' mislukt: ' .. (result.stderr or ''),
          vim.log.levels.ERROR, { ttl = 15 })
        return
      end
      local ok, decoded = pcall(vim.json.decode, result.stdout or '')
      if not ok or type(decoded) ~= 'table' then
        notify('5 vragen aan — onverwacht antwoord bij ' .. title .. '.', vim.log.levels.ERROR)
        return
      end
      on_json(decoded, tick)
    end)
  end)
end

-- Late-callbackbescherming: schrijf alleen terug als de buffer onveranderd is.
local function guarded_write(buf, tick, new_lines, ok_message)
  if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
    notify('Buffer gewijzigd tijdens genereren; niets overschreven. Draai de stap opnieuw.',
      vim.log.levels.WARN)
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  notify(ok_message)
end

local function require_source(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if not M._source_text(lines):match('%S') then
    notify('Geen brontekst gevonden. Plak eerst een uitgebreide tekst over het onderwerp.',
      vim.log.levels.WARN)
    return nil
  end
  return lines
end

function M.questions()
  local buf = vim.api.nvim_get_current_buf()
  local lines = require_source(buf)
  if not lines then return end
  run_cli(buf, { 'vragen' }, M._source_text(lines), 'vragen genereren', function(decoded, tick)
    local questions = decoded.questions or {}
    if #questions == 0 then
      notify('Geen vragen teruggekregen.', vim.log.levels.WARN)
      return
    end
    guarded_write(buf, tick, M._apply_questions(lines, questions), string.format(
      '%d vragen geplaatst. Schrap wat je niet gebruikt en draai daarna <leader>vi en <leader>vm.',
      #questions))
  end)
end

function M.intro()
  local buf = vim.api.nvim_get_current_buf()
  local lines = require_source(buf)
  if not lines then return end
  run_cli(buf, { 'intro' }, M._source_text(lines), 'kop en intro', function(decoded, tick)
    guarded_write(buf, tick, M._apply_intro(lines, decoded.headline or '', decoded.intro or ''),
      'Kop en intro geplaatst. De vragen zijn ongemoeid gelaten.')
  end)
end

function M.mail()
  local buf = vim.api.nvim_get_current_buf()
  local questions = M._read_questions(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  if #questions == 0 then
    notify('Geen vragen gevonden. Draai eerst <leader>vv en houd je selectie over.', vim.log.levels.WARN)
    return
  end
  dialog.input({ prompt = 'Naam van de geïnterviewde (voor het onderwerp)' }, function(naam)
    if not naam or not naam:match('%S') then
      notify('Geen naam opgegeven; mail niet opgesteld.', vim.log.levels.INFO)
      return
    end
    dialog.input({ prompt = 'Mailadres van de geïnterviewde' }, function(email)
      if not email or not email:match('%S') then
        notify('Geen mailadres opgegeven; mail niet opgesteld.', vim.log.levels.INFO)
        return
      end
      run_cli(buf, { 'mail', '--naam', vim.trim(naam), '--email', vim.trim(email) },
        table.concat(questions, '\n'), 'mail opstellen', function(decoded)
          local recipient = (decoded.recipients or {})[1] or vim.trim(email)
          local url = M._mailto(recipient, decoded.subject or '', decoded.body or '')
          -- Via ordered_browser (op macOS `open -g`): de mail staat klaar in je
          -- mailprogramma zonder de focus uit Neovim weg te pakken.
          if browser.open_urls({ url }) then
            notify('Mail voorbereid in je mailprogramma (op de achtergrond). Wissel ernaartoe, controleer en verstuur zelf.')
          else
            notify('Kon de mail niet voorbereiden in je mailprogramma.', vim.log.levels.ERROR)
          end
        end)
    end)
  end)
end

return M
