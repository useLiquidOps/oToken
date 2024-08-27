local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.handler(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid incoming transfer quantity"
  )

  -- amount of tokens to burn
  local quantity = bint(msg.Tags.Quantity)

  -- amount of tokens to be sent out
  local rewardQty = quantity

  -- total tokens pooled
  local totalPooled = Available + Lent
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

  -- update stored quantities (balance, available, total supply)
  Balances[msg.From] = (Balances[msg.From] or bint.zero()) - quantity
  Available = (Available or bint.zero()) - rewardQty
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
