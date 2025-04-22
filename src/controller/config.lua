local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

-- This handler can be called from the controller to update the oToken configuration
-- Note: reserved for future use in a governance model
---@type HandlerFunction
function mod.update(msg)
  -- get and parse incoming config updates
  local oracle = msg.Tags.Oracle
  local collateralFactor = tonumber(msg.Tags["Collateral-Factor"])
  local liquidationThreshold = tonumber(msg.Tags["Liquidation-Threshold"])
  local valueLimit = msg.Tags["Value-Limit"]
  local oracleDelayTolerance = tonumber(msg.Tags["Oracle-Delay-Tolerance"])
  local reserveFactor = tonumber(msg.Tags["Reserve-Factor"])

  -- validate new config values, update
  assert(
    not oracle or assertions.isAddress(oracle),
    "Invalid oracle ID"
  )
  assert(
    not collateralFactor or assertions.isPercentage(collateralFactor),
    "Invalid collateral factor"
  )
  assert(
    not liquidationThreshold or assertions.isPercentage(liquidationThreshold),
    "Invalid liquidation threshold"
  )
  assert(
    not reserveFactor or assertions.isPercentage(reserveFactor),
    "Invalid reserve factor"
  )
  assert(
    (liquidationThreshold or LiquidationThreshold) > (collateralFactor or CollateralFactor),
    "Liquidation threshold must be greater than the collateral factor"
  )

  if valueLimit then
    assert(
      assertions.isTokenQuantity(valueLimit),
      "Invalid value limit"
    )
    assert(
      bint.ult(bint.zero(), bint(valueLimit)),
      "Value limit must be higher than zero"
    )

    ValueLimit = valueLimit
  end

  if oracleDelayTolerance then
    assert(
      oracleDelayTolerance >= 0,
      "Oracle delay tolerance has to be >= 0"
    )
    assert(
      oracleDelayTolerance // 1 == oracleDelayTolerance,
      "Oracle delay tolerance has to be a whole number"
    )

    MaxOracleDelay = oracleDelayTolerance
  end

  if oracle then Oracle = oracle end
  if collateralFactor then CollateralFactor = collateralFactor end
  if liquidationThreshold then LiquidationThreshold = liquidationThreshold end
  if reserveFactor then ReserveFactor = reserveFactor end

  msg.reply({
    Oracle = Oracle,
    ["Collateral-Factor"] = tostring(CollateralFactor),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    ["Value-Limit"] = ValueLimit,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Reserve-Factor"] = tostring(reserveFactor)
  })
end

return mod
