local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function redeem(msg)
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

  -- if the total pooled and the total supply is not
  -- the same, then the reward qty will be higher
  -- than the burn qty, because there was already
  -- some interest coming in
  if not bint.eq(totalPooled, TotalSupply) then
    rewardQty = bint.udiv(
      totalPooled * quantity,
      TotalSupply
    )
  end

  -- update stored quantities (balance, available, total supply)
  Balances[msg.From] = (Balances[msg.From] or bint.zero()) - quantity
  Available = (Available or bint.zero()) - rewardQty
  TotalSupply = (TotalSupply or bint.zero()) - quantity

  ao.send({
    Target = msg.From,
    Action = "Redeem-Confirmation",
    ["Earned-Quantity"] = tostring(rewardQty),
    ["Burned-Quantity"] = tostring(quantity)
  })
end

return redeem
