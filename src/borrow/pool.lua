local json = require "json"

local mod = {}

---@type HandlerFunction
function mod.setup(msg)
  -- token that can be lent/borrowed
  CollateralID = CollateralID or ao.env.Process.Tags["Collateral-Id"]

  -- collateralization ratio
  CollateralRatio = CollateralRatio or tonumber(ao.env.Process.Tags["Collateral-Ratio"]) or 2

  -- liquidation threshold (should be lower than the collateral ratio)
  LiquidationThreshold = LiquidationThreshold or tonumber(ao.env.Process.Tags["Liquidation-Threshold"])

  -- available tokens to be lent
  Available = Available or "0"

  -- tokens borrowed by borrowers
  Lent = Lent or "0"

  -- all loans (values are Bint in string format)
  ---@type table<string, string>
  Loans = Loans or {}

  -- all interests accrued (values are Bint in string format)
  ---@type table<string, { value: string, updated: number }>
  Interests = Interests or {}

  -- base interest rate
  BaseRate = BaseRate or tonumber(ao.env.Process.Tags["Base-Rate"]) or 0

  -- initial interest rate
  InitRate = InitRate or tonumber(ao.env.Process.Tags["Init-Rate"]) or 0

  -- other oToken processes
  ---@type string[]
  Friends = Friends or json.decode(ao.env.Process.Tags.Friends or "[]")
end

---@type HandlerFunction
function mod.config(msg)
  msg.reply({
    Action = "Config",
    ["Collateral-Id"] = CollateralID,
    ["Collateral-Ratio"] = tostring(CollateralRatio),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    Oracle = Oracle,
    ["Collateral-Denomination"] = tostring(CollateralDenomination)
  })
end

return mod
