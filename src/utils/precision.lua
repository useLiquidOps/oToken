local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {
  minPrecision = 18
}

-- Returns the precision used internally for collateral quantities
-- (uses the collateral denomination to determine the correct value)
function mod.getPrecision()
  -- if the collateral denomination is precise enough,
  -- we use that for the internal precision too
  if CollateralDenomination >= mod.minPrecision then
    return CollateralDenomination
  end

  return mod.minPrecision
end

-- Returns the difference between the internal precision and the collateral denomination
function mod.getPrecisionDiff()
  -- if the collateral denomination is precise enough,
  -- we use that for the internal precision too
  if CollateralDenomination >= mod.minPrecision then
    return 0
  end

  return mod.minPrecision - CollateralDenomination
end

-- Converts a user-facing (native precision) amount into the protocol's internal 
-- high-precision representation by scaling it up by the difference between the
-- minimum precision and the collateral denomination. If the collateral denomination
-- is precise enough, it just returns the quantity
---@param nativeAmount Bint The native quantity to scale up
---@return Bint
function mod.toInternalPrecision(nativeAmount)
  -- no need to transform if the collateral's denomination is precise enough
  local precisionDiff = mod.getPrecisionDiff()
  if precisionDiff == 0 or bint.eq(nativeAmount, bint.zero()) then
    return nativeAmount
  end

  return nativeAmount * bint("1" .. string.rep("0", precisionDiff))
end

-- Converts an internal high-precision amount back into the user-facing (native 
-- token precision) format by scaling it down by the difference between the
-- minimum precision and the collateral denomination. If the collateral denomination
-- is precise enough, it just returns the quantity
-- By default the division rounds down, this can be configured with the "rounding" param
---@param internalAmount Bint The internal precise quantity to scale down
---@param rouding "roundup"|"rounddown"? Customize rounding direction
---@return Bint
function mod.toNativePrecision(internalAmount, rouding)
  -- no need to transform if the collateral's denomination is precise enough
  local precisionDiff = mod.getPrecisionDiff()
  if precisionDiff == 0 or bint.eq(internalAmount, bint.zero()) then
    return internalAmount
  end

  if rouding == "roundup" then
    return utils.udiv_roundup(
      internalAmount,
      bint("1" .. string.rep("0", precisionDiff))
    )
  end

  return bint.udiv(
    internalAmount,
    bint("1" .. string.rep("0", precisionDiff))
  )
end

-- Formats a user-facing (native precision) amount stored as a string into
-- the protocol's internal high-precision representation similarly to the
-- "toInternalPrecision()" function
---@see precision.toInternalPrecision
---@param nativeAmount string The native quantity to scale up
---@return string
function mod.formatNativeAsInternal(nativeAmount)
  if nativeAmount == "0" then return "0" end

  -- no need to transform if the collateral's denomination is precise enough
  local precisionDiff = mod.getPrecisionDiff()
  if precisionDiff == 0 then return nativeAmount end

  return nativeAmount .. string.rep("0", precisionDiff)
end

-- Converts an internal high-precision amount stored as a string back into 
-- the user-facing (native token precision) format by similarly to the
-- "toNativePrecision()" function
-- By default the division rounds down, this can be configured with the "rounding" param
---@see precision.toNativePrecision
---@param internalAmount string The internal precise quantity to scale down
---@param rouding "roundup"|"rounddown"? Customize rounding direction
---@return string
function mod.formatInternalAsNative(internalAmount, rouding)
  if internalAmount == "0" then return "0" end

  -- no need to transform if the collateral's denomination is precise enough
  local precisionDiff = mod.getPrecisionDiff()
  if precisionDiff == 0 then return internalAmount end

  if rouding == "roundup" then
    -- if the rounding direction is upwards, it's easier to just
    -- rely on the existing converter
    return tostring(mod.toNativePrecision(
      bint(internalAmount),
      rouding
    ))
  end

  -- truncate
  return string.sub(
    internalAmount,
    1,
    string.len(internalAmount) - precisionDiff
  )
end

return mod