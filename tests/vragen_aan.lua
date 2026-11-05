-- Rubriek '5 vragen aan': de bufferhelpers plaatsen vragen en kop/intro in
-- eigen secties, zodat opnieuw vragen genereren de intro niet raakt en
-- andersom. De mailstap bouwt een correcte, ge-encodeerde mailto.
local va = require('vragen_aan')

-- Brontekst → tien (hier twee) genummerde vragen onder de sectiemarkers.
local source = { 'Bron over het onderwerp.', 'Tweede regel van de bron.' }
local with_questions = va._apply_questions(source, { 'Vraag een?', 'Vraag twee?' })
local joined = table.concat(with_questions, '\n')
assert(joined:find('=== 5 VRAGEN AAN ==='), 'sectiemarker ontbreekt')
assert(joined:find('=== VRAGEN'), 'vragenmarker ontbreekt')
assert(joined:find('1%. Vraag een%?'), 'genummerde vraag 1 ontbreekt')
assert(joined:find('2%. Vraag twee%?'), 'genummerde vraag 2 ontbreekt')
assert(joined:find('Bron over het onderwerp%.'), 'bron verdween')

-- Kop + intro plaatsen laat de vragen ongemoeid.
local with_intro = va._apply_intro(with_questions, '5 Vragen aan: Jan',
  'ZWOLLE - De aanleiding.\n\nTweede alinea van de intro.')
local ij = table.concat(with_intro, '\n')
assert(ij:find('5 Vragen aan: Jan'), 'kop ontbreekt')
assert(ij:find('ZWOLLE %- De aanleiding%.'), 'intro ontbreekt')
assert(ij:find('Tweede alinea van de intro%.'), 'tweede introalinea ontbreekt')
assert(ij:find('1%. Vraag een%?') and ij:find('2%. Vraag twee%?'), 'vragen verdwenen bij intro')

-- Opnieuw vragen genereren vervangt alleen het vragenblok; de intro blijft.
local regenerated = va._apply_questions(with_intro, { 'Nieuwe vraag?' })
local rj = table.concat(regenerated, '\n')
assert(rj:find('5 Vragen aan: Jan'), 'intro verdween bij regenereren van vragen')
assert(rj:find('ZWOLLE %- De aanleiding%.'), 'introtekst verdween bij regenereren')
assert(rj:find('1%. Nieuwe vraag%?'), 'nieuwe vraag ontbreekt')
assert(not rj:find('Vraag twee%?'), 'oude vragen zijn niet vervangen')

-- Gebruiker brengt terug tot zijn selectie → _read_questions levert schone tekst.
local trimmed = va._apply_questions(with_intro, { 'Behoud deze?', 'En deze?' })
local chosen = va._read_questions(trimmed)
assert(#chosen == 2 and chosen[1] == 'Behoud deze?' and chosen[2] == 'En deze?',
  'uitlezen van de gekozen vragen klopt niet')

-- De bron blijft bron; de intro lekt er niet in.
assert(va._source_text(with_intro):find('Bron over het onderwerp%.'), 'bron niet herkend')
assert(not va._source_text(with_intro):find('5 Vragen aan: Jan'), 'intro lekt in de bron')

-- mailto: spaties en newlines percent-ge-encodeerd; ontvanger blijft leesbaar.
local url = va._mailto('rick@example.nl', '5 vragen aan: Rick', 'Hoi Rick\nVraag 1')
assert(url:find('^mailto:rick@example.nl%?subject='), 'mailto-opbouw klopt niet: ' .. url)
assert(url:find('subject=5%%20vragen%%20aan'), 'subject niet ge-encodeerd: ' .. url)
assert(url:find('body=Hoi%%20Rick%%0AVraag%%201'), 'body niet ge-encodeerd: ' .. url)

print('vragen aan: OK')

-- De echte introactie verstuurt bron en gekozen vragen afzonderlijk, met één
-- proces; de bestaande intro komt niet als nieuwe feitenbron terug.
local original_system = vim.system
local calls, respond = 0, nil
local expected_questions = chosen
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, trimmed)
vim.system = function(command, opts, done)
  calls = calls + 1
  assert(command[#command - 1] == 'intro' and command[#command] == '--input-json')
  local payload = vim.json.decode(opts.stdin)
  assert(payload.version == 1 and payload.source == va._source_text(trimmed))
  assert(vim.deep_equal(payload.selected_questions, expected_questions), 'gekozen vragen ontbreken')
  assert(not payload.source:find('5 Vragen aan: Jan', 1, true), 'oude intro werd feitenbron')
  respond = done
  return {}
end
va.intro()
assert(calls == 1 and respond)
respond({ code = 0, stdout = vim.json.encode({ headline = 'Nieuwe kop', intro = 'Alinea een.\n\nAlinea twee.' }) })
assert(vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Nieuwe kop', 1, true) ~= nil
end))
local result = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(vim.deep_equal(va._read_questions(result), chosen), 'eigen vraagselectie overschreven')
assert(va._source_text(result) == va._source_text(trimmed), 'bron overschreven')
-- Een late AI-uitkomst mag nieuwere eigen edits niet overschrijven.
va.intro()
vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Eigen nieuwe vraag?' })
local edited = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
respond({ code = 0, stdout = vim.json.encode({ headline = 'Te laat', intro = 'Oud voorstel' }) })
vim.wait(30, function() return false end)
assert(vim.deep_equal(edited, vim.api.nvim_buf_get_lines(buf, 0, -1, false)), 'nieuwere edit overschreven')
-- Intro blijft bruikbaar voordat er vragen zijn gekozen (lege JSON-array).
expected_questions = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
va.intro()
respond({ code = 0, stdout = vim.json.encode({ headline = 'Zonder vragen', intro = 'Alleen broncontext.' }) })
assert(vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'):find('Zonder vragen', 1, true) ~= nil
end))
assert(calls == 3, 'onverwachte extra AI-processen')
vim.system = original_system

-- macOS-mail omzeilt een mailto-handler zoals Chrome, zonder focus of verzending.
local notifications = require 'texttools_notify'
local messages, callback, launch = {}, nil, nil
local native_notify = notifications.workflow
notifications.workflow = function(message) messages[#messages + 1] = message end
-- vragen_aan bindt workflow bij laden; laad de module opnieuw voor deze test.
package.loaded.vragen_aan = nil
local mail = require 'vragen_aan'
vim.system = function(command, _, done)
  launch, callback = command, done
  return {}
end
assert(mail._open_mailto(url, { is_macos = true, buf = buf }))
assert(vim.deep_equal(launch, { '/usr/bin/open', '-g', '-b', 'com.apple.mail', url }),
  'mailroute gebruikte systeemhandler of nam focus')
assert(#messages == 0, 'succes gemeld voordat het openen klaar was')
callback({ code = 1, stderr = 'Mail niet beschikbaar' })
assert(vim.wait(1000, function() return #messages == 1 end))
assert(messages[1]:find('Mail niet beschikbaar', 1, true))
assert(not messages[1]:find('aangevraagd in Apple Mail', 1, true))
messages = {}
assert(mail._open_mailto(url, { is_macos = true, buf = buf }))
callback({ code = 0 })
assert(vim.wait(1000, function() return #messages == 1 end))
assert(messages[1]:find('aangevraagd in Apple Mail', 1, true))
messages = {}
vim.system = function() error('startfout') end
assert(not mail._open_mailto(url, { is_macos = true, buf = buf }))
assert(#messages == 1 and messages[1]:find('startfout', 1, true))
vim.system = original_system
notifications.workflow = native_notify

-- De mailactie vraagt alleen het mailadres; het onderwerp komt uit de kern.
local dialog = require 'user_dialog'
local saved_input, saved_open = dialog.input, mail._open_mailto
local prompts, mail_url = {}, nil
vim.api.nvim_buf_set_lines(buf, 0, -1, false, trimmed)
dialog.input = function(opts, done)
  prompts[#prompts + 1] = opts.prompt
  done('rick@example.nl')
end
mail._open_mailto = function(value) mail_url = value; return true end
vim.system = function(command, opts, done)
  assert(not vim.tbl_contains(command, '--naam'), 'onnodige naamvraag blijft bestaan')
  assert(command[#command - 1] == '--email' and command[#command] == 'rick@example.nl')
  assert(vim.tbl_contains(command, '--input-json'))
  local payload = vim.json.decode(opts.stdin)
  assert(payload.version == 1 and vim.deep_equal(payload.questions, chosen))
  local _, intro = va._split(trimmed)
  assert(payload.introduction == vim.trim(table.concat(intro, '\n')), 'kop/intro ontbreken in mail')
  assert(not opts.stdin:find('Bron over het onderwerp', 1, true), 'ruwe bron lekt mee in mail')
  done({ code = 0, stdout = vim.json.encode({ recipients = { 'rick@example.nl' },
    subject = 'Artikel de Brug: Vijf vragen aan', body = 'De vragenmail' }) })
  return {}
end
mail.mail()
assert(vim.wait(1000, function() return mail_url ~= nil end))
assert(#prompts == 1 and prompts[1] == 'Mailadres van de geïnterviewde')
assert(mail_url:find('subject=Artikel%%20de%%20Brug%%3A%%20Vijf%%20vragen%%20aan'))
assert(vim.deep_equal(va._read_questions(vim.api.nvim_buf_get_lines(buf, 0, -1, false)), chosen))
dialog.input, mail._open_mailto, vim.system = saved_input, saved_open, original_system
