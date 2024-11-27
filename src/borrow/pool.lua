local json = require "json"

local mod = {}

---@type HandlerFunction
function mod.setup(msg)
  -- token that can be lent/borrowed
  CollateralID = CollateralID or ao.env.Process.Tags["Collateral-Id"]

  -- collateralization factor
  CollateralFactor = CollateralFactor or tonumber(ao.env.Process.Tags["Collateral-Factor"]) or 2

  -- liquidation threshold (should be lower than the collateral factor)
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

  -- global current timestamp for the oracle
  Timestamp = msg.Timestamp
end

-- This syncs the global timestamp using the current message
---@type HandlerFunction
function mod.syncTimestamp(msg)
  Timestamp = msg.Timestamp
end

return mod
