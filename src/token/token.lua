local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

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

  Balances = Balances or {}
  TotalSupply = TotalSupply or "0"
end

---@type HandlerFunction
function mod.info(msg)
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
    ["Value-Limit"] = precision.formatInternalAsNative(ValueLimit, "rounddown"),
    Oracle = Oracle,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Total-Borrows"] = tostring(precision.toNativePrecision(totalLent, "roundup")),
    Cash = tostring(precision.toNativePrecision(cash, "rounddown")),
    ["Reserve-Factor"] = tostring(ReserveFactor),
    ["Total-Reserves"] = tostring(precision.toNativePrecision(reserves, "roundup")),
    ["Init-Rate"] = tostring(InitRate),
    ["Base-Rate"] = tostring(BaseRate),
    ["Jump-Rate"] = tostring(JumpRate),
    ["Kink-Param"] = tostring(KinkParam),
    ["Cooldown-Period"] = tostring(CooldownPeriod),
    Utilization = tostring(utils.bintToFloat(utilization, utilizationDecimals))
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

return mod
