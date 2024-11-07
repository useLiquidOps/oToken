local assertions = require ".utils.assertions"

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
  -- validate collateral ratio
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

return config
