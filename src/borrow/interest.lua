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

---@alias InterestPerformanceHelper { zero: Bint, totalLent: Bint, totalPooled: Bint, oneYearInMs: Bint, initRate: Bint, baseRate: Bint, rateMulWithPercentage: Bint }

-- Updates the owned interest for a single user
---@param address string User to update interests for
---@param timestamp number Current timestamp
---@param helperData InterestPerformanceHelper Helper params for performance improvements in case the function is used in a loop
function mod.updateInterest(address, timestamp, helperData)
  -- no action needed if the user does not have an active loan
  -- (we only check the interests for extra security. If there is
  -- no active loan, the interest should always be 0 or nil, because
  -- when a user repays a loan, the interest gets paid first)
  if (not Loans[address] or Loans[address] == "0") and (not Interests[address] or Interests[address].value == "0") then return end

  -- fixup interest for user, in case it is missing
  if not Interests[address] then
    Interests[address] = { value = "0", updated = timestamp }
  end

  -- calculate delay
  local delay = timestamp - Interests[address].updated

  -- no need to update if there is no delay
  if delay <= 0 then return end

  -- loan quantity and interest quantity
  local loanQty = bint(Loans[address])
  local interestQty = bint(Interests[address].value) or helperData.zero
  local yieldingQty = loanQty + interestQty

  -- calculate interest for a year
  local ownedYearlyInterest = bint.udiv(
    yieldingQty * helperData.totalLent * helperData.baseRate,
    helperData.totalPooled * helperData.rateMulWithPercentage
  ) + bint.udiv(
    yieldingQty * helperData.initRate,
    helperData.rateMulWithPercentage
  )

  -- calculate interest for the delay period
  local ownedExtraInterest = bint.udiv(
    ownedYearlyInterest * bint(delay),
    helperData.oneYearInMs
  )

  -- update interest balance for the user
  Interests[address] = {
    value = tostring(Interests[address].value + ownedExtraInterest),
    updated = timestamp
  }
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
