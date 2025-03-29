local oracleMod = require ".liquidations.oracle"
local scheduler = require ".utils.scheduler"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {
  handlers = {}
}

---@alias Position { collateralization: Bint, capacity: Bint, borrowBalance: Bint, liquidationLimit: Bint }

-- Get local position for a user (in units of the collateral)
---@param address string User address
---@return Position
function mod.position(address)
  local zero = bint.zero()

  -- result template
  ---@type Position
  local res = {
    collateralization = zero,
    capacity = zero,
    borrowBalance = zero,
    liquidationLimit = zero
  }

  -- the process holds collateral, let's calculate limits
  -- from the oToken balance (capacity, liquidation limit, etc.)
  if Balances[address] and Balances[address] ~= "0" then
    -- base data for calculations
    local balance = bint(Balances[address])
    local totalPooled = bint(Cash) + bint(TotalBorrows)

    -- the value of the balance in terms of the underlying asset
    -- (the total collateral for the user, represented by the oToken)
    res.collateralization = bint.udiv(
      totalPooled * balance,
      bint(TotalSupply)
    )

    -- local borrow capacity in units of the underlying asset
    res.capacity = bint.udiv(
      res.collateralization * bint(CollateralFactor),
      bint(100)
    )

    -- liquidation limit in units of the underlying assets
    res.liquidationLimit = bint.udiv(
      res.collateralization * bint(LiquidationThreshold),
      bint(100)
    )
  end

  -- if the user has unpaid depth (an active loan),
  -- that will be the borrow balance
  if Loans[address] and Loans[address] ~= "0" then
    res.borrowBalance = bint(Loans[address])
  end

  -- if the user has unpaid interest, that also needs
  -- to be added to the borrow balance
  if Interests[address] and Interests[address].value ~= "0" then
    res.borrowBalance = res.borrowBalance + bint(Interests[address].value or 0)
  end

  return res
end

-- Get the global position for a user (in USD, using oracle prices)
---@param address string User address
---@param oracle OracleInstance A loaded oracle instance
---@return Position
function mod.globalPosition(address, oracle)
  -- get local positions from friend processes
  local positions = scheduler.schedule(table.unpack(
    utils.map(
      ---@param friend Friend
      function (friend)
        return { Target = friend.oToken, Action = "Position", Recipient = address }
      end,
      Friends
    )
  ))

  -- load local position
  local localPosition = mod.position(address)

  -- result template
  ---@type Position
  local res = {
    collateralization = oracle.getValue(
      localPosition.collateralization,
      CollateralTicker
    ),
    capacity = oracle.getValue(
      localPosition.capacity,
      CollateralTicker
    ),
    borrowBalance = oracle.getValue(
      localPosition.borrowBalance,
      CollateralTicker
    ),
    liquidationLimit = oracle.getValue(
      localPosition.liquidationLimit,
      CollateralTicker
    )
  }

  -- calculate global position in USD
  for _, position in ipairs(positions) do
    -- the currently iterated position's collateral's ticker
    local pTicker = position.Tags["Collateral-Ticker"]

    -- parse position
    local collateralization = bint(position.Tags["Collateralization"] or 0)
    local capacity = bint(position.Tags.Capacity or 0)
    local borrowBalance = bint(position.Tags["Borrow-Balance"] or 0)
    local liquidationLimit = bint(position.Tags["Liquidation-Limit"] or 0)

    res.collateralization = res.collateralization + oracle.getValue(collateralization, pTicker)
    res.capacity = res.capacity + oracle.getValue(capacity, pTicker)
    res.borrowBalance = res.borrowBalance + oracle.getValue(borrowBalance, pTicker)
    res.liquidationLimit = res.liquidationLimit + oracle.getValue(liquidationLimit, pTicker)
  end

  return res
end

-- Local position action handler
---@type HandlerFunction
function mod.handlers.localPosition(msg)
  local account = msg.Tags.Recipient or msg.From
  local position = mod.position(account)

  msg.reply({
    ["Collateral-Ticker"] = CollateralTicker,
    ["Collateral-Denomination"] = tostring(CollateralDenomination),
    Collateralization = tostring(position.collateralization),
    Capacity = tostring(position.capacity),
    ["Borrow-Balance"] = tostring(position.borrowBalance),
    ["Liquidation-Limit"] = tostring(position.liquidationLimit)
  })
end

-- Global position action handler
---@type HandlerWithOracle
function mod.handlers.globalPosition(msg, _, oracle)
  local account = msg.Tags.Recipient or msg.From
  local position = mod.globalPosition(account, oracle)

  msg.reply({
    Collateralization = tostring(position.collateralization),
    Capacity = tostring(position.capacity),
    ["Borrow-Balance"] = tostring(position.borrowBalance),
    ["Liquidation-Limit"] = tostring(position.liquidationLimit),
    ["USD-Denomination"] = tostring(oracleMod.usdDenomination)
  })
end

-- All local user positions in this oToken
---@type HandlerFunction
function mod.handlers.allPositions(msg)
  ---@type table<string, { Collateralization: string, Capacity: string, Borrow-Balance: string, Liquidation-Limit: string }>
  local positions = {}

  -- go through all users who have collateral deposited
  -- and add their position
  for address, _ in pairs(Balances) do
    local position = mod.position(address)

    positions[address] = {
      Collateralization = tostring(position.collateralization),
      Capacity = tostring(position.capacity),
      ["Borrow-Balance"] = tostring(position.borrowBalance),
      ["Liquidation-Limit"] = tostring(position.liquidationLimit)
    }
  end

  -- go through all users who have "Loans"
  -- because it is possible that their collateralization
  -- is not in this instance of the process
  --
  -- we only need to go through the "Loans" and
  -- not the "Interests", because the interest is repaid
  -- first, the loan is only repaid after the owned
  -- interest is zero
  for address, _ in pairs(Loans) do
    -- do not handle positions that have
    -- already been added above
    if not positions[address] then
      local position = mod.position(address)

      positions[address] = {
        Collateralization = tostring(position.collateralization),
        Capacity = tostring(position.capacity),
        ["Borrow-Balance"] = tostring(position.borrowBalance),
        ["Liquidation-Limit"] = tostring(position.liquidationLimit)
      }
    end
  end

  -- reply with the serialized result
  msg.reply({
    ["Collateral-Ticker"] = CollateralTicker,
    ["Collateral-Denomination"] = tostring(CollateralDenomination),
    Data = next(positions) ~= nil and json.encode(positions) or "{}"
  })
end

return mod
