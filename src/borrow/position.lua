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

  -- TODO: the collateral ratio is actually a float, 
  -- so this should be modified

  -- capacity in units of the underlying asset
  return bint.udiv(
    balanceValue,
    CollateralRatio
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

return mod
