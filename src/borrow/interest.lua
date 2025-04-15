local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {
  context = {
    zero = bint.zero(),
    totalLent = bint.zero(),
    totalPooled = bint.zero(),
    oneYearInMs = bint("31560000000"),
    initRate = bint.zero(),
    baseRate = bint.zero(),
    rateMulWithPercentage = bint.zero()
  }
}

-- Calculates the current borrow rate
---@return Bint, number
function mod.calculateBorrowRate()
  -- helper values
  local totalLent = bint(TotalBorrows)
  local totalPooled = totalLent + bint(Cash)
  local baseRateB, rateMul = utils.floatBintRepresentation(BaseRate)
  local initRateB = utils.floatBintRepresentation(InitRate, rateMul)
  local zero = bint.zero()

  -- calculate weighted base rate
  local weightedBase = zero

  if not bint.eq(totalPooled, zero) then
    weightedBase = bint.udiv(
      baseRateB * totalLent,
      totalPooled
    )
  end

  -- full interest rate
  local interestRate = weightedBase + initRateB

  return interestRate, rateMul
end

---@type HandlerFunction
function mod.interestRate(msg)
  local interestRate, rateMul = mod.calculateBorrowRate()

  msg.reply({
    ["Annual-Percentage-Rate"] = tostring(interestRate),
    ["Rate-Multiplier"] = tostring(rateMul)
  })
end

---@type HandlerFunction
function mod.supplyRate(msg)
  ---@type Bint, number
  local borrowRate, rateMul = mod.calculateBorrowRate()
  local borrowRateFloat = utils.bintToFloat(
    borrowRate,
    math.floor(math.log(rateMul, 10))
  )

  -- calculate supply interest rate
  local le = math.log(borrowRateFloat / rateMul + 1)
  local utilizationRate = utils.bintToFloat(
    bint.udiv(
      bint(TotalBorrows),
      bint(TotalSupply)
    ),
    CollateralDenomination
  )
  local supplyRate = math.exp(
    le * (1 - ReserveFactor / 100) * utilizationRate
  ) - 1

  msg.reply({
    ["Supply-Rate"] = tostring(supplyRate)
  })
end

---@alias InterestPerformanceHelper { zero: Bint, totalLent: Bint, totalPooled: Bint, oneYearInMs: Bint, initRate: Bint, baseRate: Bint, rateMulWithPercentage: Bint }

-- Updates the owned interest for a single user and adds
-- the accrued quantity to the total borrows
---@param address string User to update interests for
---@param timestamp number Current timestamp
function mod.updateInterest(address, timestamp)
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
  local interestQty = bint(Interests[address].value) or mod.context.zero
  local yieldingQty = loanQty + interestQty

  -- calculate interest for a year
  local ownedYearlyInterest = bint.udiv(
    yieldingQty * mod.context.totalLent * mod.context.baseRate,
    mod.context.totalPooled * mod.context.rateMulWithPercentage
  ) + bint.udiv(
    yieldingQty * mod.context.initRate,
    mod.context.rateMulWithPercentage
  )

  -- calculate interest for the delay period
  local interestAccrued = bint.udiv(
    ownedYearlyInterest * bint(delay),
    mod.context.oneYearInMs
  )

  -- only update, if there is any interest accrued since
  -- the last sync
  -- this is necessary for more precise interest calculation,
  -- because it doesn't reset the time passed/delay when no
  -- update is required
  if not bint.eq(interestAccrued, mod.context.zero) then
    -- update interest balance for the user
    Interests[address] = {
      value = tostring(Interests[address].value + interestAccrued),
      updated = timestamp
    }

    -- add the interest accrued to the total borrows
    TotalBorrows = tostring(bint(TotalBorrows) + interestAccrued)
  end
end

-- Generate context data to improve the interest calculation performance
function mod.buildContext()
  -- setup the context data
  local totalLent = bint(TotalBorrows)
  local initRate, rateMul = utils.floatBintRepresentation(InitRate)

  -- update context
  mod.context = {
    zero = bint.zero(),
    totalLent = totalLent,
    totalPooled = totalLent + bint(Cash),
    oneYearInMs = bint("31560000000"),
    initRate = initRate,
    baseRate = utils.floatBintRepresentation(BaseRate, rateMul),
    rateMulWithPercentage = bint(rateMul) * bint(100)
  }
end

-- This handler function will sync the interest owned dynamically
-- based on the called Action. It is necessary for borrowing, etc.
-- to ensure collateralization
---@type HandlerFunction
function mod.syncInterests(msg)
  -- sync context data
  mod.buildContext()

  -- if the current action is "Repay", we need to update the interest
  -- not for the message sender (that is the collateral token process),
  -- but the user who initiated the transfer that resulted in the
  -- "Repay" action or the user who they are repaying on behalf of
  if msg.Tags.Action == "Repay" then
    mod.updateInterest(
      msg.Tags["X-On-Behalf"] or msg.Tags.Sender,
      msg.Timestamp
    )
  -- if the current action is "Positions", we need to update the interest
  -- for all users. this will be a heavy process, the helperData is used
  -- to optimize the loop
  elseif msg.Tags.Action == "Positions" then
    for address, _ in pairs(Loans) do
      mod.updateInterest(address, msg.Timestamp)
    end
  -- any other action that calls the interest results in syncing the
  -- message sender's interest
  else
    mod.updateInterest(msg.From, msg.Timestamp)
  end
end

-- Accrues the accumulated interest since the last update. 
-- Syncs total borrows, total reserves and the borrow index.
-- This should be used on all protocol that change the market state.
---@type HandlerFunction
function mod.accrueInterest(msg)
  -- how much time has passed since the last global borrow index update
  local deltaT = msg.Timestamp - LastBorrowIndexUpdate
  if deltaT <= 0 then return end

  -- get current borrow rate nad index, parse global values
  local borrowRate, rateMul = mod.calculateBorrowRate()
  local borrowIndex = bint(BorrowIndex)
  local totalBorrows = bint(TotalBorrows)
  local reserves = bint(Reserves)

  -- calculate interest factor (multiplied by the rateMul)
  local interestFactor = borrowRate * bint(deltaT)

  -- calculate the total interest accrued
  -- (this needs to be divided by the rateMul)
  local interestAccrued = bint.udiv(
    totalBorrows * interestFactor,
    bint(rateMul)
  )

  -- update the total borrows with the interest accrued minus the reserve fee
  totalBorrows = totalBorrows + interestAccrued

  -- update the reserves
  reserves = reserves + bint.udiv(
    interestAccrued * bint(ReserveFactor),
    bint(100)
  )

  -- update global borrow index
  borrowIndex = borrowIndex + bint.udiv(
    borrowIndex * interestFactor,
    bint(rateMul)
  )

  -- update global pool data
  LastBorrowIndexUpdate = msg.Timestamp
  TotalBorrows = tostring(totalBorrows)
  Reserves = tostring(reserves)
  BorrowIndex = tostring(borrowIndex)
end

-- Accrues interest for a specific user and returns the updated borrow balance
---@param address string User address
---@return Bint
function mod.accrueInterestForUser(address)
  -- loan for the user
  local borrowBalance = bint(Loans[address] or 0)
  if bint.eq(borrowBalance, bint.zero()) then
    return borrowBalance
  end

  -- parse global borrow index and the user's interest index
  local borrowIndex = bint(BorrowIndex)
  local interestIndex = bint(
    InterestIndices[address] or ("1" .. string.rep("0", Denomination))
  )

  -- update borrow balance and interest index for the user
  borrowBalance = bint.udiv(
    borrowBalance * borrowIndex,
    interestIndex
  )
  interestIndex = borrowIndex

  -- update global values
  Loans[address] = tostring(borrowBalance)
  Loans[interestIndex] = tostring(interestIndex)

  return borrowBalance
end

return mod
