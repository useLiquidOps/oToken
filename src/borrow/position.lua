local oracle = require ".liquidations.oracle"
local scheduler = require ".utils.scheduler"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

-- Get the local borrow capacity, based on the collateral in this pool
---@param address string Address to get the borrow capacity for
---@return Bint
function mod.getLocalBorrowCapacity(address)
  -- user loToken balance
  local balance = bint(Balances[address] or 0)

  -- total tokens pooled
  local totalPooled = bint(Available) + bint(Lent)

  -- the value of the balance in terms of the underlying asset
  local balanceValue = bint.udiv(
    totalPooled * balance,
    bint(TotalSupply)
  )

  -- multiply the collateral ratio by 1000
  -- we do this, so that we can calculate with more precise
  -- ratios below, while using bigintegers
  -- later the final result needs to be multiplied by
  -- 1000 as well, to get the actual result
  local collateralWhole, ratioMul = utils.floatBintRepresentation(CollateralRatio)

  -- capacity in units of the underlying asset
  return bint.udiv(
    balanceValue * bint(ratioMul),
    collateralWhole
  )
end

-- Get the amount of tokens borrowed + owned as interest
---@param address string Address to get the borrow capacity for
---@return Bint
function mod.getLocalUsedCapacity(address)
  return bint(Loans[address] or 0) + bint(Interests[address] or 0)
end

-- Get the global collateralization state (across all friend loTokens) in denominated USD
---@param address string Address to get the collateralization for
---@param timestamp number Current message timestamp
function mod.getGlobalCollateralization(address, timestamp)
  -- get friend values
  local friendsCollateralRes = scheduler.schedule(table.unpack(utils.map(
    function (id) return { Target = id, Action = "Collateralization", Recipient = address } end,
    Friends
  )))

  -- list capacity values separately
  ---@type PriceParam[]
  local capacities = {
    -- add local value
    { ticker = CollateralTicker, quantity = mod.getLocalBorrowCapacity(address), denomination = WrappedDenomination }
  }

  ---@type PriceParam[]
  local usedCapacities = {
    -- add local value
    {
      ticker = CollateralTicker,
      quantity = mod.getLocalUsedCapacity(address),
      denomination = WrappedDenomination
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
      quantity = msg.Tags["Used-Capacity"],
      denomination = tonumber(msg.Tags["Collateral-Denomination"])
    })
  end

  -- get collateralization values
  local zero = bint.zero()

  ---@type Bint
  local capacity = utils.reduce(
    ---@param result Bint
    ---@param v ResultItem
    function (result, v) return result + v.price end,
    zero,
    oracle.getPrice(timestamp, false, table.unpack(capacities))
  )
  ---@type Bint
  local usedCapacity = utils.reduce(
    ---@param result Bint
    ---@param v ResultItem
    function (result, v) return result + v.price end,
    zero,
    -- use ONLY the cache, so in case a price that has not been
    -- fetched correctly previously is not added here
    oracle.getPrice(timestamp, true, table.unpack(usedCapacities))
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
    ["Borrowed-Quantity"] = Loans[account],
    ["Interest-Quantity"] = Interests[account]
  })
end

---@type HandlerFunction
function mod.collateralization(msg)
  local account = msg.Tags.Recipient or msg.From

  -- get the capacity
  local capacity = mod.getLocalBorrowCapacity(account)

  -- get the used capacity
  local usedCapacity = mod.getLocalUsedCapacity(account)

  msg.reply({
    Action = "Collateralization-Response",
    Capacity = tostring(capacity),
    ["Used-Capacity"] = tostring(usedCapacity),
    ["Collateral-Ticker"] = CollateralTicker,
    ["Collateral-Denomination"] = tostring(WrappedDenomination)
  })
end

---@type HandlerFunction
function mod.globalCollateralization(msg)
  local account = msg.Tags.Recipient or msg.From

  -- reach out to friend processes
  local capacity, usedCapacity = mod.getGlobalCollateralization(account, msg.Timestamp)

  msg.reply({
    Capacity = tostring(capacity),
    ["Used-Capacity"] = tostring(usedCapacity),
    ["USD-Denomination"] = tostring(oracle.getUSDDenomination())
  })
end

return mod
