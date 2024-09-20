local mod = {}

function mod.calculateInterest()
  
end

---@type HandlerFunction
function mod.syncInterests(msg)
  -- milliseconds since the last interest sync
  local interestDelay = msg.Timestamp - LastInterestTimestamp

  if interestDelay == 0 then return end


end

return mod
