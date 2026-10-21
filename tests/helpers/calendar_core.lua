-- Kalenderwerkkeuzes zijn echte, AI-/netwerkvrije Python-contracttests.
-- Houd ze gescheiden van de nep-AI/CMS van de betreffende scenariotest.
return function(fake)
  local native = vim.system
  return function(command, options, done)
    if command[2] == '-m' and command[3] == 'texttools.calendar_preparation' then
      return native(command, options, done)
    end
    return fake(command, options, done)
  end
end
