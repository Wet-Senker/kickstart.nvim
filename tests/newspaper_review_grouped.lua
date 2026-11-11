local review = require 'newspaper_review'
local dialog = require 'user_dialog'
local asks, result = {}, nil
local native = dialog.select
dialog.select = function(items, opts, done) asks[#asks + 1] = { items = items, opts = opts, done = done } end
local choices = { { id = 'website', label = 'Alleen website' }, { id = 'use_web', label = 'Webtekst behouden' } }
local plan = { contract_version = 1, items = {
  { edition = 'B', publication_name = 'De Brug', newspaper_date = '2026-11-10', reason = 'Dezelfde aanleiding', choices = choices },
  { edition = 'SW', publication_name = 'De Swollenaer', newspaper_date = '2026-11-11', reason = 'Dezelfde aanleiding', choices = choices },
}, groups = { { editions = { 'B', 'SW' }, reason = 'Dezelfde aanleiding' } } }
review.collect(plan, {}, function(value) result = value end)
assert(#asks == 1 and asks[1].opts.prompt:find('De Brug', 1, true) and asks[1].opts.prompt:find('De Swollenaer', 1, true))
assert(asks[1].opts.prompt:find('Dezelfde aanleiding', 1, true))
asks[1].done(nil, 2)
assert(result.B == 'use_web' and result.SW == 'use_web' and #asks == 1)
asks, result = {}, nil
review.collect(plan, {}, function(value) result = value end)
for i, item in ipairs(asks[1].items) do if item:find('Per krant kiezen', 1, true) then asks[1].done(nil, i); break end end
assert(#asks == 2 and asks[2].opts.prompt:find('De Brug', 1, true))
asks[2].done(nil, 1)
assert(not result and #asks == 3)
asks[3].done(nil, 2)
assert(result.B == 'website' and result.SW == 'use_web')
-- Filtering answered editions must also filter the source groups.
local filtered = vim.deepcopy(plan); filtered.items = { filtered.items[2] }
asks, result = {}, nil
review.collect(filtered, {}, function(value) result = value end)
asks[1].done(nil, 2)
assert(result.SW == 'use_web' and result.B == nil)
asks, result = {}, 'pending'
review.collect(plan, {}, function(value) result = value end)
asks[1].done(nil, nil)
assert(result == nil)
dialog.select = native
print('grouped newspaper review: OK')
