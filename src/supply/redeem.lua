local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.handler(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid redeem quantity"
  )

  -- amount of tokens to burn
  local quantity = bint(msg.Tags.Quantity)

  -- loToken wallet balance for sender
  local walletBalance = bint(Balances[msg.From] or "0")

  -- check if the user has enough tokens to burn
  assert(
    bint.ule(quantity, walletBalance),
    "Not enough tokens to burn for this wallet"
  )

  -- amount of tokens to be sent out
  local rewardQty = quantity

  -- total tokens pooled
  local availableTokens = bint(Available)
  local totalPooled = availableTokens + bint(Lent)
  local totalSupply = bint(TotalSupply)

  -- if the total pooled and the total supply is not
  -- the same, then the reward qty will be higher
  -- than the burn qty, because there was already
  -- some interest coming in
  if not bint.eq(totalPooled, totalSupply) then
    rewardQty = bint.udiv(
      totalPooled * quantity,
      totalSupply
    )
  end

  -- make sure there is enough tokens available to redeem for
  assert(
    bint.ult(rewardQty, availableTokens),
    "Not enough available tokens to redeem for"
  )

  -- update stored quantities (balance, available, total supply)
  Balances[msg.From] = tostring(walletBalance - quantity)
  Available = tostring(availableTokens - rewardQty)
  TotalSupply = tostring(totalSupply - quantity)

  msg.reply({
    Action = "Redeem-Confirmation",
    ["Earned-Quantity"] = tostring(rewardQty),
    ["Burned-Quantity"] = tostring(quantity)
  })
end

---@param msg Message
---@param _ Message
---@param err unknown
function mod.error(msg, _, err)
  msg.reply({
    Action = "Redeem-Error",
    ["Refund-Quantity"] = msg.Tags.Quantity,
    Error = tostring(err),
  })
end

return mod
