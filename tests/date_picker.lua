local picker = require('date_picker')
local dialog = require('user_dialog')
local menus, result = {}, nil
dialog.select = function(items, opts, done) menus[#menus + 1] = { items = items, opts = opts, done = done } end
local days = picker.days(0, '2026-10-23')
assert(#days == 7 and days[1].date == '2026-10-23' and days[7].date == '2026-10-29', 'wintertijd verstoort kalenderdagen')
assert(picker.days(1, '2026-12-28')[1].date == '2027-01-04', 'jaarwisseling')
picker.choose({ today = '2026-10-13', suggested = '2026-10-20', offset = 1, indefinite = true }, function(value) result = value end)
assert(menus[1].items[1].value == '2026-10-20' and menus[1].opts.default == 1)
assert(menus[1].items[1].label:find('voorgesteld', 1, true))
assert(menus[1].opts.native == true)
menus[1].done(menus[1].items[8]) -- Vorige week.
assert(menus[2].items[1].value == '2026-10-13')
menus[2].done(menus[2].items[#menus[2].items])
assert(result == 'indefinite')
picker.choose({ today = '2026-10-13' }, function(value) result = value or 'cancelled' end)
menus[3].done(nil)
assert(result == 'cancelled')
print('date picker: OK')
