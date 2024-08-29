local oracle = require ".liquidations.oracle"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.capacity(msg)
  local account = msg.Tags.Target or msg.From

  -- user loToken balance
  local balance = bint(Balances[account] or 0)

  -- total tokens pooled
  local totalPooled = bint(Available) + bint(Lent)

  -- the value of the balance in terms of the underlying asset
  local balanceValue = bint.udiv(
    totalPooled * balance,
    bint(TotalSupply)
  )

  -- capacity in units of the underlying asset
  local capacity = bint.udiv(
    balanceValue,
    CollateralRatio
  )

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
