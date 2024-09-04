local oracle = require ".liquidations.oracle"
local bint = require ".utils.bint"(1024)

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
  local ratioMul = 1000
  local collateralWhole = bint(CollateralRatio * ratioMul // 1)

  -- capacity in units of the underlying asset
  return bint.udiv(
    balanceValue * bint(ratioMul),
    collateralWhole
  )
end

---@type HandlerFunction
function mod.capacity(msg)
  local account = msg.Tags.Target or msg.From

  -- get the capacity in the wrapped token
  local capacity = mod.getLocalBorrowCapacity(account)

  -- calculate USD value of the capacity
  local capacityUSD = oracle.getUnderlyingPrice(capacity)

  -- reply with the results
  msg.reply({
    Action = "Borrow-Capacity-Response",
    Value = tostring(capacity),
    ["USD-Value"] = tostring(capacityUSD)
  })
end

---@type HandlerFunction
function mod.balance(msg)
  local account = msg.Tags.Target or msg.From

  msg.reply({
    Action = "Borrow-Balance-Response",
    ["Borrowed-Quantity"] = Loans[account],
    ["Interest-Quantity"] = Interests[account]
  })
end

---@type HandlerFunction
function mod.collateralization(msg)
  local account = msg.Tags.Target or msg.From

  -- get the capacity in USD
  local capacity = oracle.getUnderlyingPrice(
    mod.getLocalBorrowCapacity(account)
  )

  -- get the used capacity (with the oracle cached price)
  local usedCapacity = oracle.getUnderlyingPrice(
    bint(Loans[account] or 0) + bint(Interests[account] or 0),
    true
  )

  msg.reply({
    Action = "User-Collateralization",
    Capacity = tostring(capacity),
    ["Used-Capacity"] = tostring(usedCapacity)
  })
end

return mod
