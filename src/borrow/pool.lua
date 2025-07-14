local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local json = require "json"

local mod = {}

---@type HandlerFunction
function mod.setup(msg)
  assert(
    assertions.isAddress(ao.env.Process.Tags["Collateral-Id"]),
    "Invalid collateral id"
  )

  -- AO token process
  AOToken = AOToken or ao.env.Process.Tags["AO-Token"] or "0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc"

  -- token that can be lent/borrowed
  CollateralID = CollateralID or ao.env.Process.Tags["Collateral-Id"]

  -- collateralization factor
  CollateralFactor = CollateralFactor or tonumber(ao.env.Process.Tags["Collateral-Factor"]) or 50

  -- liquidation threshold (should be greater than the collateral factor)
  LiquidationThreshold = LiquidationThreshold or tonumber(ao.env.Process.Tags["Liquidation-Threshold"]) or CollateralFactor + 5

  -- available tokens to be lent
  Cash = Cash or "0"

  -- tokens borrowed by borrowers
  TotalBorrows = TotalBorrows or "0"

  -- all loans (values are Bint in string format)
  ---@type table<string, string>
  Loans = Loans or {}

  -- user interest indexes (in Bint string), denominated
  -- in the borrow index denomination
  ---@type table<string, string>
  InterestIndices = InterestIndices or {}

  -- last time the global borrow index was updated
  LastBorrowIndexUpdate = BorrowIndex == nil and msg.Timestamp or LastBorrowIndexUpdate

  -- global borrow index (in Bint string)
  -- the borrow index is always denominated in
  -- the borrow index denomination
  -- (initialised as 1)
  BorrowIndex = BorrowIndex or ("1" .. string.rep("0", precision.getPrecision()))

  -- base interest rate
  BaseRate = BaseRate or tonumber(ao.env.Process.Tags["Base-Rate"]) or 1

  -- jump interest rate
  JumpRate = JumpRate or tonumber(ao.env.Process.Tags["Jump-Rate"]) or 1

  -- initial interest rate
  InitRate = InitRate or tonumber(ao.env.Process.Tags["Init-Rate"]) or 1

  -- kink parameter for the utilization rate after which
  -- the jump rate is applied (in percentage)
  KinkParam = KinkParam or tonumber(ao.env.Process.Tags["Kink-Param"]) or 80

  -- other oToken processes
  -- a friend consists of the following fields:
  -- - id: string (this is the address of the collateral supported by LiquidOps)
  -- - ticker: string (the ticker of the collateral)
  -- - oToken: string (the address of the oToken process for the collateral)
  -- - denomination: integer (the denomination of the collateral)
  -- this corresponds with the tokens list in the controller (minus the current oToken instance)
  ---@type Friend[]
  Friends = Friends or json.decode(ao.env.Process.Tags.Friends or "[]") or {}

  -- limit the value of an interaction
  -- (in units of the collateral)
  ValueLimit = ValueLimit or precision.formatNativeAsInternal(ao.env.Process.Tags["Value-Limit"] or "0")

  -- global current timestamp and block for the oracle
  Timestamp = msg.Timestamp
  Block = msg["Block-Height"]

  -- reserves
  ReserveFactor = ReserveFactor or tonumber(ao.env.Process.Tags["Reserve-Factor"]) or 0
  Reserves = Reserves or "0"

  -- enabled functionalities
  EnabledInteractions = EnabledInteractions or {
    mint = true,
    redeem = true,
    borrow = true,
    repay = true,
    transfer = true,
    liquidation = true
  }
end

-- This syncs the global timestamp and block using the current message
---@type HandlerFunction
function mod.syncTimestamp(msg)
  Timestamp = msg.Timestamp
  Block = msg["Block-Height"]
end

return mod
