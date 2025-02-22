local Oracle = require ".liquidations.oracle"
local scheduler = require ".utils.scheduler"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {}

-- Get the local borrow capacity, based on the collateral in this pool, the
-- current collateralization and the liquidation threshold
---@param address string Address to get the borrow capacity for
---@return Bint, Bint, Bint
function mod.getLocalBorrowCapacity(address)
  local zero = bint.zero()

  -- optimize 0 results
  if not Balances[address] or Balances[address] == "0" then
    return zero, zero, zero
  end

  -- user oToken balance
  local balance = bint(Balances[address] or 0)

  -- total tokens pooled
  local totalPooled = bint(Available) + bint(Lent)

  -- the value of the balance in terms of the underlying asset
  -- (the total collateral represented by the oToken)
  local collateralization = bint.udiv(
    totalPooled * balance,
    bint(TotalSupply)
  )

  -- local borrow capacity in units of the underlying asset
  local capacity = bint.udiv(
    collateralization * bint(CollateralFactor),
    bint(100)
  )

  -- liquidation threshold in units of the underlying assets
  local threshold = bint.udiv(
    collateralization * bint(LiquidationThreshold),
    bint(100)
  )

  return capacity, collateralization, threshold
end

-- Get the amount of tokens borrowed + owned as interest
---@param address string Address to get the borrow capacity for
---@return Bint
function mod.getLocalUsedCapacity(address)
  -- optimize 0 results
  if (not Loans[address] or Loans[address] == "0") and (not Interests[address] or Interests[address].value == "0") then
    return bint.zero()
  end

  return bint(Loans[address] or 0) + bint((Interests[address] and Interests[address].value) or 0)
end

-- Get the global collateralization state (across all friend oTokens) in denominated USD
---@param address string Address to get the collateralization for
function mod.getGlobalCollateralization(address)
  -- get friend values
  local friendsCollateralRes = scheduler.schedule(table.unpack(utils.map(
    function (id) return { Target = id, Action = "Position", Recipient = address } end,
    Friends
  )))

  -- list capacity values separately
  ---@type PriceParam[]
  local capacities = {
    -- add local value
    { ticker = CollateralTicker, quantity = mod.getLocalBorrowCapacity(address), denomination = CollateralDenomination }
  }

  ---@type PriceParam[]
  local usedCapacities = {
    -- add local value
    {
      ticker = CollateralTicker,
      quantity = mod.getLocalUsedCapacity(address),
      denomination = CollateralDenomination
    }
  }

  for _, msg in ipairs(friendsCollateralRes) do
    table.insert(capacities, {
      ticker = msg.Tags["Collateral-Ticker"],
      quantity = bint(msg.Tags.Capacity),
      denomination = tonumber(msg.Tags["Collateral-Denomination"])
    })
    table.insert(usedCapacities, {
      ticker = msg.Tags["Collateral-Ticker"],
      quantity = bint(msg.Tags["Used-Capacity"]),
      denomination = tonumber(msg.Tags["Collateral-Denomination"])
    })
  end

  -- get collateralization values
  local zero = bint.zero()

  -- TODO: this could be optimized
  -- (in cases where the "usedCapacities" has some tokens that
  -- are not in the "capacities", the prices are requested 2x.
  -- these could be requested in one price request)

  ---@type Bint
  local capacity = utils.reduce(
    ---@param result Bint
    ---@param v ResultItem
    function (result, v) return result + v.price end,
    zero,
    oracle.getPrice(table.unpack(capacities))
  )
  ---@type Bint
  local usedCapacity = utils.reduce(
    ---@param result Bint
    ---@param v ResultItem
    function (result, v) return result + v.price end,
    zero,
    oracle.getPrice(table.unpack(usedCapacities))
  )

  return capacity, usedCapacity
end

---@type HandlerFunction
function mod.capacity(msg)
  local account = msg.Tags.Recipient or msg.From

  -- get the capacity in the wrapped token
  local capacity = mod.getLocalBorrowCapacity(account)

  -- reply with the results
  msg.reply({
    Action = "Borrow-Capacity-Response",
    ["Borrow-Capacity"] = tostring(capacity)
  })
end

---@type HandlerFunction
function mod.balance(msg)
  local account = msg.Tags.Recipient or msg.From

  msg.reply({
    Action = "Borrow-Balance-Response",
    ["Borrowed-Quantity"] = Loans[account] or "0",
    ["Interest-Quantity"] = Interests[account] and Interests[account].value or "0"
  })
end

---@type HandlerFunction
function mod.position(msg)
  local account = msg.Tags.Recipient or msg.From

  -- get the capacity
  local capacity, totalCollateral = mod.getLocalBorrowCapacity(account)

  -- get the used capacity
  local usedCapacity = mod.getLocalUsedCapacity(account)

  msg.reply({
    Action = "Collateralization-Response",
    Capacity = tostring(capacity),
    ["Used-Capacity"] = tostring(usedCapacity),
    ["Total-Collateral"] = tostring(totalCollateral),
    ["Collateral-Ticker"] = CollateralTicker,
    ["Collateral-Denomination"] = tostring(CollateralDenomination)
  })
end

---@type HandlerFunction
function mod.globalPosition(msg)
  local account = msg.Tags.Recipient or msg.From

  -- reach out to friend processes
  local capacity, usedCapacity = mod.getGlobalCollateralization(account)

  msg.reply({
    Capacity = tostring(capacity),
    ["Used-Capacity"] = tostring(usedCapacity),
    ["USD-Denomination"] = tostring(oracle.getUSDDenomination())
  })
end

---@type HandlerFunction
function mod.allPositions(msg)
  ---@type table<string, { Capacity: string, Used-Capacity: string }>
  local positions = {}

  -- go through all users who have collateral deposited
  -- and add their position
  for address, _ in pairs(Balances) do
    local capacity, totalCollateral = mod.getLocalBorrowCapacity(address)

    positions[address] = {
      Capacity = tostring(capacity),
      ["Used-Capacity"] = tostring(mod.getLocalUsedCapacity(address)),
      ["Total-Collateral"] = tostring(totalCollateral)
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
      local capacity, totalCollateral = mod.getLocalBorrowCapacity(address)

      positions[address] = {
        Capacity = tostring(capacity),
        ["Used-Capacity"] = tostring(mod.getLocalUsedCapacity(address)),
        ["Total-Collateral"] = tostring(totalCollateral)
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
