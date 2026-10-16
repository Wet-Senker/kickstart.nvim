package.preload['fidget.progress'] = function()
  return {
    handle = {
      create = function()
        return { finish = function() end }
      end,
    },
  }
end
package.preload['fidget.notification'] = function()
  return { notify = function() end }
end

local ai = require 'ai_text'

local original_system = vim.system
local original_notify = vim.notify
local calls = {}
local post_rewrite_calls = {}
local original_post_rewrite = ai._post_full_article_rewrite

ai._post_full_article_rewrite = function(options)
  table.insert(post_rewrite_calls, options)
  if options.after_start then options.after_start() end
end

vim.notify = function() end

vim.system = function(cmd, opts, callback)
  table.insert(calls, { cmd = cmd, opts = opts })
  callback {
    code = 0,
    stdout = 'Feestelijk concert\n\nKAMPEN - Het concert begint om 20.00 uur.\n',
    stderr = '',
  }
  return { kill = function() end }
end

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  'e: B',
  '',
  '=== ARTIKEL ===',
  '',
  'Fantastisch feestelijk concert',
  '',
  'KAMPEN - Het indrukwekkende concert begint om 20.00 uur.',
})

ai.journalistic_neutralize()
assert(
  vim.wait(1000, function() return vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == 'Feestelijk concert' end, 10),
  'neutraliteitsresultaat werd niet in de body geplaatst'
)
assert(#calls == 1, 'neutraliteitsactie startte niet exact één AI-call')
assert(calls[1].cmd[2] == 'journalistiek_neutraliseren', 'verkeerde prompt gestart')
assert(calls[1].opts.stdin:find('Fantastisch feestelijk concert', 1, true), 'artikelbody ontbrak in AI-input')
assert(not calls[1].opts.stdin:find('e: B', 1, true), 'controlecode kwam in AI-input terecht')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == 'e: B', 'controlecode ging verloren bij neutraliseren')
assert(#post_rewrite_calls == 1, 'neutraliseren startte de gedeelde herschrijfnacontrole niet')
assert(post_rewrite_calls[1].controls[1] == 'e: B', 'nacontrole kreeg de controleregels niet')
assert(post_rewrite_calls[1].document:find('Feestelijk concert', 1, true), 'nacontrole kreeg de nieuwe tekst niet')
assert(post_rewrite_calls[1].original_content:find('Fantastisch feestelijk concert', 1, true),
  'nacontrole kreeg de oorspronkelijke tekst niet')

-- Een resultaat dat na een nieuwere gebruikersbewerking arriveert, blijft weg.
vim.system = function(_, _, callback)
  vim.api.nvim_buf_set_lines(buf, 4, 5, false, { 'Eigen nieuwere kop' })
  callback { code = 0, stdout = 'Oude AI-kop\n', stderr = '' }
  return { kill = function() end }
end
ai.journalistic_neutralize()
assert(
  vim.wait(1000, function() return vim.api.nvim_buf_get_lines(buf, 4, 5, false)[1] == 'Eigen nieuwere kop' end, 10),
  'laat AI-resultaat overschreef een nieuwere bufferbewerking'
)
assert(#post_rewrite_calls == 1, 'verouderd neutraliteitsresultaat startte toch nacontroles')

-- Praktische lijstjes mogen proza worden; controls, frontmatter en losse
-- social-/kalender-/redactiesecties blijven buiten de schrijfopdracht.
local concert = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(concert)
local protected_sections = {
  '---', '', '## Facebook', '', 'Bestaande Facebooktekst.', '',
  '## LinkedIn', '', 'Bestaande LinkedIntekst.', '',
  '## Kalender', '', 'Titel: Concert', 'Tijd: 20:00', '',
  '## Niet voor publicatie', '', '> Alleen voor de redactie: Testpersoon.',
}
local concert_lines = {
  '---', 'source_document:', '  id: test-concert', '---', '',
  'e: B, SUGGESTIE, SW', "suggestiereden: SW — plaatsnaam ‘Zwolle’", '',
  '=== ARTIKEL ===', '', 'Allerzielenconcert', '',
  'KAMPEN - Op maandag 2 november is er een concert.', '',
  'Praktische informatie', '', 'Aanvang: 20.00 uur', 'Kerk open: 19.15 uur', '',
}
vim.list_extend(concert_lines, protected_sections)
vim.api.nvim_buf_set_lines(concert, 0, -1, false, concert_lines)
local concert_input
local edited_concert = 'Allerzielenconcert\n\n**KAMPEN - Het concert is op maandag 2 november.**\n\n'
  .. 'Het concert begint om 20.00 uur; de kerk gaat om 19.15 uur open.'
vim.system = function(command, opts, callback)
  concert_input = opts.stdin
  assert(command[2] == 'journalistiek_neutraliseren', 'AN veranderde van kernactie')
  callback { code = 0, stdout = edited_concert, stderr = '' }
  return { kill = function() end }
end
ai.journalistic_neutralize()
assert(vim.wait(1000, function() return #post_rewrite_calls == 2 end, 10), 'concertnacontrole ontbrak')
assert(concert_input:find('Praktische informatie', 1, true), 'publieke praktische info ontbrak in AI-input')
for _, private in ipairs { 'source_document', 'suggestiereden', 'Facebook', 'LinkedIn', 'Kalender', 'Testpersoon' } do
  assert(not concert_input:find(private, 1, true), private .. ' kwam onterecht in AI-input')
end
local concert_result = table.concat(vim.api.nvim_buf_get_lines(concert, 0, -1, false), '\n')
assert(concert_result:find(edited_concert, 1, true), 'praktische proza werd niet toegepast')
assert(concert_result:find('source_document:\n  id: test-concert', 1, true), 'frontmatter ging verloren')
assert(concert_result:find('e: B, SUGGESTIE, SW', 1, true), 'editiekeuzes gingen verloren')
assert(concert_result:find(table.concat(protected_sections, '\n'), 1, true), 'beschermde secties veranderden')

-- Een geweigerde waarde-/citaatcontrole houdt ook deze volledige buffer intact.
vim.system = function(_, _, callback)
  callback { code = 1, stdout = '', stderr = 'Neutraliteitscontrole geweigerd: gewijzigde tijd.' }
  return { kill = function() end }
end
ai.journalistic_neutralize()
vim.wait(100, function() return false end, 10)
assert(concert_result == table.concat(vim.api.nvim_buf_get_lines(concert, 0, -1, false), '\n'),
  'een geweigerd resultaat veranderde het concertdocument')
assert(#post_rewrite_calls == 2, 'geweigerd resultaat startte toch nacontroles')

ai._post_full_article_rewrite = original_post_rewrite

-- Regressie: als minimaal publicatieklaar maken voor het eerst een betrouwbare
-- dateline oplevert, gebruikt de gedeelde nacontrole die meteen voor e:.
local original_formatter = ai.tussenkopjes_streamer
local original_duplicate_runner = ai._duplicate_stage_runner
ai.tussenkopjes_streamer = function()
  error('neutraliseren startte onterecht automatische opmaak')
end
ai._duplicate_stage_runner = function(_, callback)
  callback(false, { performed = true, candidates = {} })
end
vim.system = function(command, opts, callback)
  if command[1]:match('aitext$') then
    callback {
      code = 0,
      stdout = 'Halloween Spooktocht\n\n**ZWOLLE - De spooktocht vindt plaats in Zwolle Zuid.**\n',
      stderr = '',
    }
    return { kill = function() end }
  end
  return original_system(command, opts, callback)
end

local zwolle = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(zwolle)
vim.api.nvim_buf_set_lines(zwolle, 0, -1, false, {
  '=== ARTIKEL ===', '', 'Halloween Spooktocht in Zwolle Zuid', '',
  'De populaire tocht wordt opnieuw gehouden in Zwolle Zuid.',
})
ai.journalistic_neutralize()
assert(
  vim.wait(5000, function()
    return table.concat(vim.api.nvim_buf_get_lines(zwolle, 0, -1, false), '\n')
      :find('e: SW', 1, true) ~= nil
  end, 20),
  'nieuwe betrouwbare dateline zette e: SW niet na neutraliseren'
)

ai.tussenkopjes_streamer = original_formatter
ai._duplicate_stage_runner = original_duplicate_runner
vim.system = original_system
vim.notify = original_notify

print 'journalistic neutrality: OK'
