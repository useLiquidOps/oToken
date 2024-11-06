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
function config.setCollateralRatio(msg)
  -- validate collateral ratio
  local ratio = tonumber(msg.Tags["Collateral-Ratio"])

  assert(
    ratio ~= nil and type(ratio) == "number",
    "Invalid ratio provided"
  )

  -- update
  CollateralRatio = ratio

  -- notify the user
  msg.reply({
    Action = "Collateral-Ratio-Set",
    ["Collateral-Ratio"] = tostring(ratio)
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
