local json = require "json"

local mod = {}

---@type HandlerFunction
function mod.setup(msg)
  -- token that can be lent/borrowed
  Token = Token or ao.env.Process.Tags.Token

  -- collateralization ratio
  CollateralRatio = CollateralRatio or tonumber(ao.env.Process.Tags["Collateral-Ratio"])

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
  ---@type table<string, string>
  Interests = Interests or {}

  -- last time interests have been synced
  LastInterestTimestamp = LastInterestTimestamp or msg.Timestamp

  -- base interest ratio
  BaseRate = BaseRate or tonumber(BaseRate)

  -- initial interest ratio
  InitRate = InitRate or tonumber(InitRate)

  -- other loToken processes
  ---@type string[]
  Friends = Friends or json.decode(ao.env.Process.Tags.Friends or "[]")
end

---@type HandlerFunction
function mod.config(msg)
  msg.reply({
    Action = "Config",
    Token = Token,
    ["Collateral-Ratio"] = tostring(CollateralRatio),
    ["Liquidation-Threshold"] = tostring(LiquidationThreshold),
    Oracle = Oracle,
    ["Collateral-Denomination"] = tostring(CollateralDenomination)
  })
end

return mod
