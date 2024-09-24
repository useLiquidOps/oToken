local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.syncInterests(msg)
  -- milliseconds since the last interest sync
  local interestDelay = msg.Timestamp - LastInterestTimestamp

  if interestDelay == 0 then return end

  -- helper values for calculation
  local zero = bint.zero()
  local totalLent = bint(Lent)
  local totalPooled = totalLent + bint(Available)
  local interestDelayB = bint(interestDelay)
  local oneYearInMs = bint("31560000000")

  -- go through all Loans and add the interest
  for address, rawQty in pairs(Loans) do
    if rawQty ~= nil and rawQty ~= "0" then
      -- loan quantity and interest quantity
      local loanQty = bint(rawQty)
      local interestQty = Interests[address] and bint(Interests[address]) or zero
      local yieldingQty = loanQty + interestQty

      -- calculate missing interest
      local ownedInterest = bint.udiv(
        yieldingQty * totalLent * interestDelayB,
        totalPooled * oneYearInMs
      )

      -- add owned interest
      Interests[address] = tostring(interestQty + ownedInterest)
    end
  end
end

return mod
