package.preload['fidget.progress'] = function()
  return { handle = { create = function() return { finish = function() end } end } }
end
local ai, notices = require('ai_text'), require('texttools_notify')
local system, post = vim.system, ai._post_full_article_rewrite
local runner = ai._duplicate_stage_runner
local function buffer()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false,
    { 'e: B', '', '=== ARTIKEL ===', '', 'Kop', '', 'Artikeltekst.' })
  return buf
end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n') end
local social = { '', '---', '', '## Facebook', '', 'Nieuwste Facebooktekst.', '', '## LinkedIn', '', 'Nieuwe LinkedIntekst.' }
local function append(buf) vim.api.nvim_buf_set_lines(buf, -1, -1, false, social) end
local function wait(test) assert(vim.wait(1200, test, 5)) end
ai._post_full_article_rewrite = function() end

-- AN: kopmetadata en nieuwe staart blijven behouden, ook na de voorstelreview.
for _, review in ipairs({ false, true }) do
  local buf, callback, source = buffer(), nil, nil
  vim.system = function(_, opts, done) callback, source = done, opts.stdin; return {} end
  ai.journalistic_neutralize()
  append(buf)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { 'e: SW', 'c: Nieuwe fotograaf' })
  callback({ code = 0, stderr = '', stdout = vim.json.encode { version = 1,
    source_sha256 = vim.fn.sha256(source), status = review and 'needs_review' or 'ready',
    article = 'Nieuwe kop\n\nBewerkte artikeltekst.',
    issues = review and { { code = 'numbers', message = 'Controleer de wijziging.' } } or {} } })
  if review then
    wait(function() return vim.b.texttools_proposal_review == true end)
    -- Nog een edit buiten de body terwijl de vergelijkingsweergave open is.
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Extra socialregel.' })
    vim.cmd('ArtikelBewerkingOvernemen')
  end
  wait(function() return text(buf):find('Bewerkte artikeltekst.', 1, true) end)
  assert(text(buf):find('e: SW\nc: Nieuwe fotograaf', 1, true))
  assert(text(buf):find('Nieuwste Facebooktekst.', 1, true) and text(buf):find('Nieuwe LinkedIntekst.', 1, true))
  if review then assert(text(buf):find('Extra socialregel.', 1, true)) end
end

-- Een echte bodywijziging tijdens AN wordt nog steeds nooit overschreven.
do
  local buf, callback, source = buffer(), nil, nil
  vim.system = function(_, opts, done) callback, source = done, opts.stdin; return {} end
  ai.journalistic_neutralize()
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Zelf bijgewerkt.' })
  callback { code = 0, stdout = vim.json.encode { version = 1, source_sha256 = vim.fn.sha256(source),
    status = 'ready', article = 'Oud resultaat', issues = {} } }
  vim.wait(30)
  assert(text(buf):find('Zelf bijgewerkt.', 1, true) and not text(buf):find('Oud resultaat', 1, true))
end

-- AR: socials tijdens editieresolutie en tijdens AI mogen de taak niet stoppen.
do
  local buf, resolve, rewrite = buffer(), nil, nil
  ai._mark_duplicate_check_done(buf)
  vim.system = function(cmd, _, done)
    if vim.tbl_contains(cmd, '--resolve-editions') then resolve = done else rewrite = done end
    return {}
  end
  ai.rewrite_article_buffer()
  append(buf)
  resolve { code = 0, stdout = '{"editions":["B"],"has_explicit_editions":true}', stderr = '' }
  wait(function() return rewrite ~= nil end)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Social tijdens AI.' })
  rewrite { code = 0, stdout = 'Nieuwe kop\n\nNieuwe artikeltekst.', stderr = '' }
  wait(function() return text(buf):find('Nieuwe artikeltekst.', 1, true) end)
  assert(text(buf):find('Nieuwste Facebooktekst.', 1, true) and text(buf):find('Social tijdens AI.', 1, true))
end

-- AR: body-edits tijdens de doublurescan starten AI met de nieuwste body,
-- niet met de oude; die leescontrole wordt niet opnieuw gestart.
do
  local buf, scan, scans, rewrite_input = buffer(), nil, 0, nil
  ai._duplicate_stage_runner = function(_, done) scan, scans = done, scans + 1 end
  vim.system = function(cmd, opts, done)
    if vim.tbl_contains(cmd, '--resolve-editions') then
      done { code = 0, stdout = '{"editions":["B"],"has_explicit_editions":true}', stderr = '' }
    else rewrite_input = opts.stdin; done { code = 1, stderr = 'Offline teststop' } end
    return {}
  end
  ai.rewrite_article_buffer()
  wait(function() return scan ~= nil end)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Tijdens controle aangevuld.' })
  scan(true, { version = 1, performed = true, candidates = {} })
  wait(function() return rewrite_input ~= nil end)
  assert(scans == 1 and rewrite_input:find('Tijdens controle aangevuld.', 1, true))
end

-- Verzenden: scan voltooit, maar publicatie van het oude snapshot blijft verboden.
do
  local buf, scan, ready = buffer(), nil, nil
  ai._duplicate_stage_runner = function(_, done) scan = done end
  ai._check_duplicate_stage(buf, { 'B' }, 'verzenden', function(ok) ready = ok end)
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, { 'Nieuwere inhoud.' })
  scan(true, { version = 1, performed = true, candidates = {} })
  assert(ready == false and text(buf):find('Nieuwere inhoud.', 1, true))
  assert(not ai._duplicate_check_is_current(buf))
end

-- Kalenderstate: een social tijdens de korte lokale opslag leidt tot een
-- veilige herberekening op de huidige buffer, zonder extra AI.
do
  local buf, pending, calls, finished = buffer(), nil, 0, nil
  vim.system = function(cmd, opts, done)
    assert(vim.tbl_contains(cmd, 'texttools.calendar_preparation'))
    pending, calls = { data = vim.json.decode(opts.stdin), done = done }, calls + 1
    return {}
  end
  ai._calendar_transition(buf, 'force', {}, function(data) finished = data end)
  append(buf)
  pending.done { code = 0, stdout = vim.json.encode { version = 1, markdown = pending.data.markdown, status = 'forced' } }
  wait(function() return calls == 2 end)
  assert(pending.data.markdown:find('Nieuwste Facebooktekst.', 1, true))
  pending.done { code = 0, stdout = vim.json.encode { version = 1, markdown = pending.data.markdown, status = 'forced' } }
  wait(function() return finished ~= nil end)
  assert(text(buf):find('Nieuwste Facebooktekst.', 1, true))
end
vim.system, ai._post_full_article_rewrite, ai._duplicate_stage_runner = system, post, runner
print('article task scopes: OK')
