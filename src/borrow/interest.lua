local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

---@type HandlerFunction
function mod.interestRate(msg)
  -- helper values
  local totalLent = bint(Lent)
  local baseRateB, rateMul = utils.floatBintRepresentation(BaseRate)
  local initRateB = utils.floatBintRepresentation(InitRate, rateMul)

  -- calculate weighted base rate
  local weightedBase = bint.udiv(
    baseRateB * totalLent,
    (totalLent + bint(Available))
  )

  -- full interest rate
  local interestRate = weightedBase + initRateB

  msg.reply({
    ["Annual-Percentage-Rate"] = tostring(interestRate),
    ["Rate-Multiplier"] = tostring(rateMul)
  })
end

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
  local initRateB, rateMul = utils.floatBintRepresentation(InitRate)
  local baseRateB = utils.floatBintRepresentation(BaseRate, rateMul)
  local rateMulWithPercentage = bint(rateMul) * bint(100)

  -- go through all Loans and add the interest
  for address, rawQty in pairs(Loans) do
    if rawQty ~= nil and rawQty ~= "0" then
      -- loan quantity and interest quantity
      local loanQty = bint(rawQty)
      local interestQty = Interests[address] and bint(Interests[address]) or zero
      local yieldingQty = loanQty + interestQty

      -- calculate interest for a year
      local ownedYearlyInterest = bint.udiv(
        yieldingQty * totalLent * baseRateB,
        totalPooled * rateMulWithPercentage
      ) + bint.udiv(yieldingQty * initRateB, rateMulWithPercentage)

      -- calculate interest for the delay period
      local ownedInterest = bint.udiv(
        ownedYearlyInterest * interestDelayB,
        oneYearInMs
      )

      -- add owned interest
      Interests[address] = tostring(interestQty + ownedInterest)
    end
  end

  LastInterestTimestamp = msg.Timestamp
end

return mod
