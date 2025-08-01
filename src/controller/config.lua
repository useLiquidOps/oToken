local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)

local mod = {}

-- This handler can be called from the controller to update the oToken configuration
-- Note: reserved for future use in a governance model
---@type HandlerFunction
function mod.update(msg)
  -- get and parse incoming config updates
  local newOracle = msg.Tags.Oracle
  local newCollateralFactor = tonumber(msg.Tags["Collateral-Factor"])
  local newLiquidationThreshold = tonumber(msg.Tags["Liquidation-Threshold"])
  local newValueLimit = msg.Tags["Value-Limit"]
  local newOracleDelayTolerance = tonumber(msg.Tags["Oracle-Delay-Tolerance"])
  local newReserveFactor = tonumber(msg.Tags["Reserve-Factor"])
  local newKinkParam = tonumber(msg.Tags["Kink-Param"])
  local newBaseRate = tonumber(msg.Tags["Base-Rate"])
  local newJumpRate = tonumber(msg.Tags["Jump-Rate"])
  local newInitRate = tonumber(msg.Tags["Init-Rate"])
  local newCooldownPeriod = tonumber(msg.Tags["Cooldown-Period"])
  local newWrappedAOToken = msg.Tags["Wrapped-AO-Token"]
  local newAOToken = msg.Tags["AO-Token"]

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
  assert(
    not newKinkParam or assertions.isPercentage(newKinkParam),
    "Invalid kink param"
  )
  assert(
    not newBaseRate or assertions.isValidNumber(newBaseRate),
    "Invalid base rate"
  )
  assert(
    not newJumpRate or assertions.isValidNumber(newJumpRate),
    "Invalid jump rate"
  )
  assert(
    not newInitRate or assertions.isValidNumber(newInitRate),
    "Invalid init rate"
  )
  assert(
    not newCooldownPeriod or assertions.isValidInteger(newCooldownPeriod),
    "Invalid cooldown period"
  )
  assert(
    not newWrappedAOToken or assertions.isAddress(newWrappedAOToken),
    "Invalid Wrapped AO token process ID"
  )
  assert(
    not newAOToken or assertions.isAddress(newAOToken),
    "Invalid AO token process ID"
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
  if newValueLimit then ValueLimit = precision.formatNativeAsInternal(newValueLimit) end
  if newOracleDelayTolerance then MaxOracleDelay = newOracleDelayTolerance end
  if newKinkParam then KinkParam = newKinkParam end
  if newBaseRate then BaseRate = newBaseRate end
  if newJumpRate then JumpRate = newJumpRate end
  if newInitRate then InitRate = newInitRate end
  if newCooldownPeriod then CooldownPeriod = newCooldownPeriod end
  if newWrappedAOToken then WrappedAOToken = newWrappedAOToken end
  if newAOToken then AOToken = newAOToken end

  msg.reply({
    Oracle = Oracle,
    ["Collateral-Factor"] = tostring(CollateralFactor),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    ["Value-Limit"] = precision.formatInternalAsNative(ValueLimit, "rounddown"),
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Reserve-Factor"] = tostring(ReserveFactor),
    ["Kink-Param"] = tostring(KinkParam),
    ["Base-Rate"] = tostring(BaseRate),
    ["Jump-Rate"] = tostring(JumpRate),
    ["Init-Rate"] = tostring(InitRate),
    ["AO-Token"] = tostring(AOToken),
    ["Wrapped-AO-Token"] = tostring(WrappedAOToken)
  })
end

-- Handler to enable interactions
---@type HandlerFunction
function mod.toggleInteractions(msg)
  local updatedInteractions = {}

  for name, value in pairs(EnabledInteractions) do
    local expectedTagName = string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    updatedInteractions[name] = value

    if msg.Tags[expectedTagName] ~= nil then
      updatedInteractions[name] = msg.Tags[expectedTagName] == "Enabled"
    end
  end

  EnabledInteractions = updatedInteractions

  msg.reply({ Updated = "true" })
end

return mod
