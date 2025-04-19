local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.update(msg)
  -- get and parse incoming config updates
  local newOracle = msg.Tags.Oracle
  local newCollateralFactor = tonumber(msg.Tags["Collateral-Factor"])
  local newLiquidationThreshold = tonumber(msg.Tags["Liquidation-Threshold"])
  local newValueLimit = msg.Tags["Value-Limit"]
  local newOracleDelayTolerance = tonumber(msg.Tags["Oracle-Delay-Tolerance"])
  local newReserveFactor = tonumber(msg.Tags["Reserve-Factor"])

  -- validate new config values, update
  assert(
    not newOracle or assertions.isAddress(newOracle),
    "Invalid oracle ID"
  )
  assert(
    not newCollateralFactor or assertions.isPercentage(newCollateralFactor),
    "Invalid collateral factor"
  )
  assert(
    not newLiquidationThreshold or assertions.isPercentage(newLiquidationThreshold),
    "Invalid liquidation threshold"
  )
  assert(
    not newReserveFactor or assertions.isPercentage(newReserveFactor),
    "Invalid reserve factor"
  )
  assert(
    (newLiquidationThreshold or LiquidationThreshold) > (newCollateralFactor or CollateralFactor),
    "Liquidation threshold must be greater than the collateral factor"
  )

  if newValueLimit then
    assert(
      assertions.isTokenQuantity(newValueLimit),
      "Invalid value limit"
    )
    assert(
      bint.ult(bint.zero(), bint(newValueLimit)),
      "Value limit must be higher than zero"
    )
  end

  if newOracleDelayTolerance then
    assert(
      newOracleDelayTolerance >= 0,
      "Oracle delay tolerance has to be >= 0"
    )
    assert(
      newOracleDelayTolerance // 1 == newOracleDelayTolerance,
      "Oracle delay tolerance has to be a whole number"
    )
  end

  if newOracle then Oracle = newOracle end
  if newCollateralFactor then CollateralFactor = newCollateralFactor end
  if newLiquidationThreshold then LiquidationThreshold = newLiquidationThreshold end
  if newReserveFactor then ReserveFactor = newReserveFactor end
  if newValueLimit then ValueLimit = newValueLimit end
  if newOracleDelayTolerance then MaxOracleDelay = newOracleDelayTolerance end

  msg.reply({
    Oracle = Oracle,
    ["Collateral-Factor"] = tostring(CollateralFactor),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    ["Value-Limit"] = ValueLimit,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Reserve-Factor"] = tostring(ReserveFactor)
  })
end

return mod
