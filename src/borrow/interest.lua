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
  -- setup the helper data
  local totalLent = bint(Lent)
  local initRate, rateMul = utils.floatBintRepresentation(InitRate)

  ---@type InterestPerformanceHelper
  local helperData = {
    zero = bint.zero(),
    totalLent = totalLent,
    totalPooled = totalLent + bint(Available),
    oneYearInMs = bint("31560000000"),
    initRate = initRate,
    baseRate = utils.floatBintRepresentation(BaseRate, rateMul),
    rateMulWithPercentage = bint(rateMul) * bint(100)
  }

  -- if the current action is "Repay", we need to update the interest
  -- not for the message sender (that is the collateral token process),
  -- but the user who initiated the transfer that resulted in the
  -- "Repay" action or the user who they are repaying on behalf of
  if msg.Tags.Action == "Repay" then
    mod.updateInterest(
      msg.Tags["X-On-Behalf"] or msg.Tags.Sender,
      msg.Timestamp,
      helperData
    )
  -- if the current action is "Positions", we need to update the interest
  -- for all users. this will be a heavy process, the helperData is used
  -- to optimize the loop
  elseif msg.Tags.Action == "Positions" then
    for address, _ in pairs(Loans) do
      mod.updateInterest(address, msg.Timestamp, helperData)
    end
  -- any other action that calls the interest results in syncing the
  -- message sender's interest
  else
    mod.updateInterest(msg.From, msg.Timestamp, helperData)
  end
end

return mod
