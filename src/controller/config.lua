local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local config = {}

---@type HandlerFunction
function config.setOracle(msg)
  -- validate oracle address
  local newOracle = msg.Tags.Oracle

  assert(
    assertions.isAddress(newOracle),
    "Invalid oracle ID"
  )

  -- update
  Oracle = newOracle

  -- notify the user
  msg.reply({
    Action = "Oracle-Set",
    Oracle = newOracle
  })
end

---@type HandlerFunction
function config.setCollateralFactor(msg)
  -- validate collateral factor
  local factor = tonumber(msg.Tags["Collateral-Factor"])

  assert(
    factor ~= nil and type(factor) == "number",
    "Invalid ratio provided"
  )

  -- update
  CollateralFactor = factor

  -- notify the user
  msg.reply({
    Action = "Collateral-Factor-Set",
    ["Collateral-Factor"] = tostring(factor)
  })
end

---@type HandlerFunction
function config.setLiquidationThreshold(msg)
  -- validate threshold
  local threshold = tonumber(msg.Tags["Liquidation-Threshold"])

  assert(
    threshold ~= nil and type(threshold) == "number",
    "Invalid threshold provided"
  )

  -- update
  LiquidationThreshold = threshold

  -- notify the user
  msg.reply({
    Action = "Liquidation-Threshold-Set",
    ["Liquidation-Threshold"] = tostring(threshold)
  })
end

---@type HandlerFunction
function config.setValueLimit(msg)
  local newLimit = msg.Tags["Value-Limit"]

  -- validate limit
  assert(
    assertions.isTokenQuantity(newLimit),
    "Invalid value limit"
  )
  assert(
    bint.ult(bint.zero(), bint(newLimit)),
    "Value limit must be higher than zero"
  )

  -- update
  ValueLimit = newLimit

  -- notify the sender
  msg.reply({
    Action = "Value-Limit-Set",
    ["Value-Limit"] = newLimit
  })
end

function config.setOracleDelayTolerance(msg)
  local newTolerance = tonumber(msg.Tags["Oracle-Delay-Tolerance"])

  -- validate new tolerance
  assert(
    newTolerance ~= nil,
    "Invalid or no delay tolerance provided"
  )
  assert(
    newTolerance >= 0,
    "Delay tolerance has to be >= 0"
  )
  assert(
    newTolerance // 1 == newTolerance,
    "Delay tolerance has to be a whole number"
  )

  -- update
  MaxOracleDelay = newTolerance

  -- notify the sender
  msg.reply({
    Action = "Oracle-Delay-Tolerance-Set",
    ["Oracle-Delay-Tolerance"] = msg.Tags["Oracle-Delay-Tolerance"]
  })
end

return config
