local json = require "json"

local mod = {}

---@type HandlerFunction
function mod.setup()
  CollateralTicker = ao.env.Process.Tags["Collateral-Ticker"]
  Ticker = "o" .. CollateralTicker
  Name = "LiquidOps " .. (ao.env.Process.Tags["Collateral-Name"] or CollateralTicker)
  Logo = ao.env.Process.Tags.Logo

  -- the wrapped token's denomination
  CollateralDenomination = tonumber(ao.env.Process.Tags["Collateral-Denomination"] or 0) or 0

  Denomination = CollateralDenomination or 12
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
    ["Reserve-Factor"] = tostring(ReserveFactor),
    ["Value-Limit"] = ValueLimit,
    Oracle = Oracle,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay)
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
