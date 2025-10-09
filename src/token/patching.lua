local precision = require ".utils.precision"
local interest = require ".borrow.interest"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

---@type HandlerFunction
function mod.setup()
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

  -- enabled and disabled interactions
  local enabledInteractions = {}
  local disabledInteractions = {}

  for name, enabled in pairs(EnabledInteractions) do
    table.insert(
      enabled and enabledInteractions or disabledInteractions,
      string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
    )
  end

  -- clone loans, interest indices, balances
  local loans = mod.mapAsTrie(Loans)
  local interestIndices = mod.mapAsTrie(InterestIndices)
  local balances = mod.mapAsTrie(Balances)

  -- current interest rate
  local interestRate, rateMul = interest.calculateBorrowRate()
  local borrowRate = utils.bintToFloat(
    interestRate,
    select(2, string.gsub(tostring(rateMul), "0", ""))
  )

  -- map positions
  local positions = { device = "trie@1.0" }
  local calculatedPositions = mod.allPositions()

  for address, position in pairs(calculatedPositions) do
    positions[address] = {
      collateralization = tostring(position.collateralization),
      capacity = tostring(position.capacity),
      borrowBalance = tostring(position.borrowBalance),
      liquidationLimit = tostring(position.liquidationLimit)
    }
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
      ["total-borrows"] = tostring(precision.toNativePrecision(totalLent, "roundup")),
      cash = tostring(precision.toNativePrecision(cash, "rounddown")),
      ["total-reserves"] = tostring(precision.toNativePrecision(reserves, "roundup")),
      utilization = tostring(utils.bintToFloat(utilization, utilizationDecimals)),
      rates = {
        borrow = borrowRate,
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

return mod
