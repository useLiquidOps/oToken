local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

-- Calculates the current borrow rate
---@return Bint, number
function mod.calculateBorrowRate()
  -- helper values
  local totalLent = bint(TotalBorrows)
  local totalPooled = totalLent + bint(Cash) - bint(Reserves)
  local baseRateB, rateMul = utils.floatBintRepresentation(BaseRate)
  local initRateB = utils.floatBintRepresentation(InitRate, rateMul)
  local jumpRateB = utils.floatBintRepresentation(JumpRate, rateMul)
  local kinkParamB = utils.floatBintRepresentation(KinkParam, rateMul)

  local zero = bint.zero()
  local hundred = bint(100)
  local rateMulB = bint(rateMul)

  -- calculate weighted base rate
  local weightedBase = zero

  if not bint.eq(totalPooled, zero) then
    -- utilization rate in percentage, scaled up by the
    -- rateMul so it can be compared to the kink param
    local util = bint.udiv(
      totalLent * hundred * rateMulB,
      totalPooled
    )

    -- below the kink param, the interest rate is linear
    -- with a gentle slope
    if bint.ule(util, kinkParamB) then
      -- normal interest rate:
      -- initRate + utilizationRate * baseRate

      -- the weighted base rate is the utilization rate
      -- multiplied by the base rate
      weightedBase = bint.udiv(
        baseRateB * totalLent,
        totalPooled
      )
    else
      -- jump interest rate:
      -- initRate + kinkUtilizationRate * baseRate + (utilizationRate - kinkUtilizationRate) * jumpRate

      -- apply jump rate
      -- use the kink param to calculate rate(kink)
      weightedBase = bint.udiv(
        baseRateB * kinkParamB,
        hundred * rateMulB
      )

      -- add jump weighted value
      weightedBase = weightedBase + bint.udiv(
        jumpRateB * (util - kinkParamB),
        hundred * rateMulB
      )
    end
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
  local totalBorrows = bint(TotalBorrows)
  local totalPooled = bint(Cash) + totalBorrows - bint(Reserves)
  local supplyRate = 0

  if not bint.eq(totalPooled, 0) then
    local le = math.log(borrowRateFloat + 1)
    local utilizationRate = bint.tonumber(totalBorrows) / bint.tonumber(totalPooled)

    supplyRate = math.exp(
      le * (1 - ReserveFactor / 100) * utilizationRate
    ) - 1
  end

  msg.reply({ ["Supply-Rate"] = tostring(supplyRate) })
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
  local oneYearInMs = bint("31560000000")

  -- calculate interest factor (multiplied by the rateMul)
  local interestFactor = borrowRate * bint(deltaT)

  -- calculate the total interest accrued
  -- (this needs to be divided by the rateMul)
  local interestAccrued = bint.udiv(
    totalBorrows * interestFactor,
    bint(rateMul) * oneYearInMs
  )

  -- the remainder of the reserves division for precision
  ReservesRemainder = ReservesRemainder or "0"

  -- update the reserves
  local reservesUpdate, remainder = bint.udivmod(
    interestAccrued * bint(ReserveFactor) + bint(ReservesRemainder),
    bint(100)
  )

  -- update the reserves remainder value
  ReservesRemainder = tostring(remainder)

  -- update global borrow index
  local borrowIndexUpdate = bint.udiv(
    borrowIndex * interestFactor,
    bint(rateMul) * oneYearInMs
  )

  -- return early if the state doesn't change
  local zero = bint.zero()

  if
    bint.eq(borrowIndexUpdate, zero) or
    bint.eq(reservesUpdate, zero) or
    bint.eq(interestAccrued, zero)
  then return end

  -- update global pool data
  LastBorrowIndexUpdate = msg.Timestamp
  TotalBorrows = tostring(totalBorrows + interestAccrued)
  Reserves = tostring(reserves + reservesUpdate)
  BorrowIndex = tostring(borrowIndex + borrowIndexUpdate)
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
    InterestIndices[address] or ("1" .. string.rep("0", precision.getPrecision()))
  )

  -- update borrow balance and interest index for the user
  borrowBalance = bint.udiv(
    borrowBalance * borrowIndex,
    interestIndex
  )
  interestIndex = borrowIndex

  -- update global values
  Loans[address] = tostring(borrowBalance)
  InterestIndices[address] = tostring(interestIndex)

  return borrowBalance
end

return mod
