local precision = require ".utils.precision"
local position = require ".borrow.position"
local interest = require ".borrow.interest"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {
  utils = {}
}

---@type HandlerFunction
function mod.setup()
  PatchingSetUp = PatchingSetUp or false
  if PatchingSetUp then return end

  -- enabled and disabled interactions
  local enabledInteractions, disabledInteractions = mod.utils.interactionsState()

  -- clone loans, interest indices, balances
  local loans = mod.mapAsTrie(Loans)
  local interestIndices = mod.mapAsTrie(InterestIndices)
  local balances = mod.mapAsTrie(Balances)

  -- map positions
  local positions = { device = "trie@1.0" }
  local calculatedPositions = position.allPositions()

  for address, pos in pairs(calculatedPositions) do
    positions[address] = mod.utils.stringValPosition(pos)
  end

  ao.send({
    device = "patch@1.0",
    ["token-info"] = {
      name = Name,
      ticker = Ticker,
      logo = Logo,
      denomination = tostring(Denomination),
      supply = TotalSupply
    },
    environment = {
      collateral = {
        id = CollateralID,
        denomination = CollateralDenomination
      },
      ["risk-parameters"] = {
        ["collateral-factor"] = CollateralFactor,
        ["liquidation-threshold"] = LiquidationThreshold,
        ["reserve-factor"] = ReserveFactor
      },
      limits = {
        ["value-limit"] = precision.formatInternalAsNative(ValueLimit, "rounddown"),
        ["cooldown-period"] = CooldownPeriod,
        ["enabled-interactions"] = enabledInteractions,
        ["disabled-interactions"] = disabledInteractions
      },
      ["oracle-parameters"] = {
        oracle = Oracle,
        ["oracle-delay-tolerance"] = MaxOracleDelay
      },
      ["interest-model"] = {
        rates = {
          init = InitRate,
          base = BaseRate,
          jump = JumpRate
        },
        ["kink-param"] = KinkParam
      },
      friends = Friends
    },
    ["pool-state"] = {
      ["total-borrows"] = precision.formatInternalAsNative(TotalBorrows, "roundup"),
      cash = precision.formatInternalAsNative(Cash, "rounddown"),
      ["total-reserves"] = precision.formatInternalAsNative(Reserves, "roundup"),
      utilization = mod.utils.utilization(),
      rates = {
        borrow = mod.utils.borrowRate(),
        supply = interest.calculateSupplyRate()
      },
      ["interest-accrual"] = {
        ["borrow-index"] = BorrowIndex,
        ["last-updated"] = LastBorrowIndexUpdate,
        ["reserves-remainder"] = ReservesRemainder
      }
    },
    balances = balances,
    cooldowns = Cooldowns,
    positions = positions,
    loans = loans,
    ["interest-indices"] = interestIndices,
    orders = { device = "trie@1.0" }
  })

  PatchingSetUp = true
end

-- Add a param to the patch message going out after all handlers were executed
---@param data table The data to patch
function mod.patch(data)
  utils.patch_table(Patch, data)
end

-- Patch the result of a borrow/mint/redeem/repay
---@param id string The ID of the message that initiated the order (pushed for or message id)
---@param success boolean The result of the order
---@param message string? Optional result message
function mod.patchOrder(id, success, message)
  ao.send({
    device = "patch@1.0",
    orders = {
      [id] = {
        success = success,
        message = message
      }
    }
  })
end

-- Convert a map to a trie structure when patching
---@generic T : unknown
---@param map table<string, T> The map to convert
---@return table<string, T>
function mod.mapAsTrie(map)
  local res = { device = "trie@1.0" }

  for key, value in pairs(map) do
    res[key] = value
  end

  return res
end

function mod.utils.utilization()
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

  return utils.bintToFloatString(utilization, utilizationDecimals)
end

function mod.utils.borrowRate()
  local interestRate, rateMul = interest.calculateBorrowRate()

  return utils.bintToFloatString(
    interestRate,
    select(2, string.gsub(tostring(rateMul), "0", ""))
  )
end

function mod.utils.interactionsState()
  local enabled = {}
  local disabled = {}

  for name, isEnabled in pairs(EnabledInteractions) do
    table.insert(
      isEnabled and enabled or disabled,
      string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    )
  end

  return enabled, disabled
end

-- Make position values strings from Bint
---@param pos Position The position to transform
function mod.utils.stringValPosition(pos)
  return {
    collateralization = tostring(pos.collateralization),
    capacity = tostring(pos.capacity),
    borrowBalance = tostring(pos.borrowBalance),
    liquidationLimit = tostring(pos.liquidationLimit)
  }
end

return mod
