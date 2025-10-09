local precision = require ".utils.precision"
local interest = require ".borrow.interest"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

---@type HandlerFunction
function mod.setup()
  -- parse as bint
  local totalLent = bint(TotalBorrows)
  local cash = bint(Cash)
  local reserves = bint(Reserves)

  -- calculate utilization
  local totalPooled = totalLent + cash - reserves
  local utilizationDecimals = 5
  local utilization = bint.zero()

  if not bint.eq(totalPooled, 0) then
    utilization = bint.udiv(
      totalLent * bint(100) * bint.ipow(10, utilizationDecimals),
      totalPooled
    )
  end

  -- enabled and disabled interactions
  local enabledInteractions = {}
  local disabledInteractions = {}

  for name, enabled in pairs(EnabledInteractions) do
    table.insert(
      enabled and enabledInteractions or disabledInteractions,
      string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    )
  end

  -- clone loans, interest indices, balances
  local loans = mod.mapAsTrie(Loans)
  local interestIndices = mod.mapAsTrie(InterestIndices)
  local balances = mod.mapAsTrie(Balances)

  -- current interest rate
  local interestRate, rateMul = interest.calculateBorrowRate()
  local borrowRate = utils.bintToFloat(
    interestRate,
    select(2, string.gsub(tostring(rateMul), "0", ""))
  )

  -- map positions
  local positions = { device = "trie@1.0" }
  local calculatedPositions = mod.allPositions()

  for address, position in pairs(calculatedPositions) do
    positions[address] = {
      collateralization = tostring(position.collateralization),
      capacity = tostring(position.capacity),
      borrowBalance = tostring(position.borrowBalance),
      liquidationLimit = tostring(position.liquidationLimit)
    }
  end

  ao.send({
    device = "patch@1.0",
    ["token-info"] = {
      name = Name,
      ticker = Ticker,
      logo = Logo,
      denomination = tostring(Denomination),
      supply = TotalSupply,
      collateralId = CollateralID,
      collateralFactor = tostring(CollateralFactor),
      collateralDenomination = tostring(CollateralDenomination),
      liquidationThreshold = tostring(LiquidationThreshold),
      valueLimit = precision.formatInternalAsNative(ValueLimit, "rounddown"),
      oracle = Oracle,
      oracleDelayTolerance = tostring(MaxOracleDelay),
      totalBorrows = tostring(precision.toNativePrecision(totalLent, "roundup")),
      cash = tostring(precision.toNativePrecision(cash, "rounddown")),
      reserveFactor = tostring(ReserveFactor),
      totalReserves = tostring(precision.toNativePrecision(reserves, "roundup")),
      initRate = tostring(InitRate),
      baseRate = tostring(BaseRate),
      jumpRate = tostring(JumpRate),
      kinkParam = tostring(KinkParam),
      cooldownPeriod = tostring(CooldownPeriod),
      utilization = tostring(utils.bintToFloat(utilization, utilizationDecimals)),
      enabledInteractions = enabledInteractions,
      disabledInteractions = disabledInteractions
    },
    balances = balances,
    friends = Friends,
    cooldowns = Cooldowns,
    borrowRate = borrowRate,
    supplyRate = interest.calculateSupplyRate(),
    positions = positions,
    loans = loans,
    borrowIndex = BorrowIndex,
    lastBorrowIndexUpdate = LastBorrowIndexUpdate,
    reservesRemainder = ReservesRemainder,
    interestIndices = interestIndices,
    orders = { device = "trie@1.0" }
  })
end

-- Patch the result of a borrow/mint/redeem/repay
---@param id string The ID of the message that initiated the order (pushed for or message id)
---@param success boolean The result of the order
---@param message string? Optional result message
function mod.patchOrder(id, success, message)
  ao.send({
    device = "patch@1.0",
    orders = {
      [id] = {
        success = success,
        message = message
      }
    }
  })
end

-- Convert a map to a trie structure when patching
---@generic T : unknown
---@param map table<string, T> The map to convert
---@return table<string, T>
function mod.mapAsTrie(map)
  local res = { device = "trie@1.0" }

  for key, value in pairs(map) do
    res[key] = value
  end

  return res
end

return mod
