local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

local defaultCollateralPrecision = 18

---@type HandlerFunction
function mod.setup()
  assert(
    ao.env.Process.Tags["Collateral-Ticker"] ~= nil,
    "No collateral id"
  )

  CollateralTicker = ao.env.Process.Tags["Collateral-Ticker"]
  Ticker = "o" .. CollateralTicker
  Name = "LiquidOps " .. (ao.env.Process.Tags["Collateral-Name"] or CollateralTicker)
  Logo = ao.env.Process.Tags.Logo or nil

  -- the wrapped token's denomination
  CollateralDenomination = tonumber(ao.env.Process.Tags["Collateral-Denomination"] or 0) or 0

  if CollateralDenomination == 0 then
    Denomination = 12
  else
    Denomination = CollateralDenomination
  end

  -- the local quantities of the collateral are stored with extra precision for
  -- tokens with a denomination below 18
  CollateralPrecision = CollateralDenomination > defaultCollateralPrecision and CollateralDenomination or defaultCollateralPrecision

  Balances = Balances or {}
  TotalSupply = TotalSupply or "0"
end

---@param msg Message
function mod.info(msg)
  msg.reply({
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination),
    ["Total-Supply"] = TotalSupply,
    ["Collateral-Id"] = CollateralID,
    ["Collateral-Factor"] = tostring(CollateralFactor),
    ["Collateral-Denomination"] = tostring(CollateralDenomination),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    ["Value-Limit"] = ValueLimit,
    Oracle = Oracle,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Total-Borrows"] = TotalBorrows,
    Cash = Cash,
    ["Reserve-Factor"] = tostring(ReserveFactor),
    ["Total-Reserves"] = Reserves
  })
end

---@param msg Message
function mod.total_supply(msg)
  msg.reply({
    ["Total-Supply"] = TotalSupply,
    Ticker = Ticker,
    Data = TotalSupply
  })
end

-- Transform a collateral quantity to conform to the internal
-- storage precision
---@param qty Bint The quantity to transform in the collateral's native denomination
function mod.toLocalPrecision(qty)
  -- no need to transform if the collateral's denomination is precise enough
  if CollateralDenomination >= defaultCollateralPrecision then
    return qty
  end

  -- difference between the collateral's denomination and the local precision
  local precisionDiff = CollateralPrecision - CollateralDenomination

  return qty * bint("1" .. string.rep("0", precisionDiff))
end

-- Transform a quantity with the internal storage precision
-- to conform to the collateral's denomination
---@param qty Bint The quantity to transform with the internal storage precision
---@param roundUp boolean? Optionally round up the result
function mod.toNativeDenomination(qty, roundUp)
  -- no need to transform if the collateral's denomination is precise enough
  if CollateralDenomination >= defaultCollateralPrecision then
    return qty
  end

  -- difference between the collateral's denomination and the local precision
  local precisionDiff = CollateralPrecision - CollateralDenomination

  if roundUp then
    return utils.udiv_roundup(
      qty,
      bint("1" .. string.rep("0", precisionDiff))
    )
  end

  return bint.udiv(
    qty,
    bint("1" .. string.rep("0", precisionDiff))
  )
end

return mod
