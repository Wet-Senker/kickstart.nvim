require('context_help').setup()
local review = require('edition_review').setup { notify = function() end }

local source = vim.api.nvim_create_buf(true, true)
local workspace = {
  ready = false,
  variants = {
    {
      code = 'B',
      name = 'Algemene versie voor De Brug, De Stadskoerier, Nieuwsbode de Kop',
      editions = { 'B', 'ST', 'K' },
      content = 'Regionale tekst',
      status = 'review',
    },
    {
      code = 'SW',
      name = 'De Swollenaer',
      editions = { 'SW' },
      content = 'Zwolse tekst',
      status = 'review',
    },
  },
}

local buffers = review._refresh_review_buffers(source, workspace, { force = true })
assert(#buffers == 2, 'gedeelde groep moet één reviewbuffer krijgen')
local shared_name = vim.api.nvim_buf_get_name(buffers[1])
assert(shared_name:find('Gedeelde krantversie B/ST/K', 1, true), 'gedeelde groep ontbreekt in buffertitel')
assert(shared_name:find('Algemene versie voor De Brug, De Stadskoerier, Nieuwsbode de Kop', 1, true),
  'gedeelde bestemmingen ontbreken in buffertitel')
local shared_help = review._review_help_entry(buffers[1])
assert(shared_help.title == 'Krantversie · Algemene versie voor De Brug, De Stadskoerier, Nieuwsbode de Kop',
  'contexthelp noemt de gedeelde bestemmingen niet')
assert(table.concat(shared_help.sections[2].lines, '\n'):find('voor deze gedeelde groep', 1, true),
  'socialhulp behandelt een gedeelde groep als één krant')

local single_name = vim.api.nvim_buf_get_name(buffers[2])
assert(single_name:find('Krantversie SW', 1, true), 'eigen editie verloor haar normale titel')
assert(not single_name:find('Gedeelde krantversie', 1, true), 'eigen editie is onterecht gedeeld')

print('edition review shared label: OK')
