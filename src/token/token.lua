local precision = require ".utils.precision"

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
    ["Value-Limit"] = precision.formatInternalAsNative(ValueLimit, "rounddown"),
    Oracle = Oracle,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    ["Total-Borrows"] = precision.formatInternalAsNative(TotalBorrows, "roundup"),
    Cash = precision.formatInternalAsNative(Cash, "rounddown"),
    ["Reserve-Factor"] = tostring(ReserveFactor),
    ["Total-Reserves"] = precision.formatInternalAsNative(Reserves, "roundup")
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
