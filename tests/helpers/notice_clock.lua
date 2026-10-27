-- Vaste gebeurtenistijd voor presentatietests; andere klokformaten blijven echt.
local original = os.date
os.date = function(format, ...)
  if format == '%H:%M' then return '12:34' end
  return original(format, ...)
end
