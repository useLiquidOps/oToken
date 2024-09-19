local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

-- Get the price of the oToken in terms of the underlying asset
function mod.getPrice(quantity)
  return bint.udiv(
    totalPooled * quantity,
    bint(TotalSupply)
  )
end

---@type HandlerFunction
function mod.handler(msg)
  -- default qty
  local quantity = bint.one()

  -- optional provided qty
  if msg.Tags.Quantity then
    assert(
      assertions.isTokenQuantity(msg.Tags.Quantity),
      "Invalid token quantity"
    )
    quantity = bint(msg.Tags.Quantity)
  end

  -- total tokens pooled
  local totalPooled = bint(Available) + bint(Lent)

  -- calculate price based on the underlying value of the total supply
  local returnPrice = bint.udiv(
    totalPooled * quantity,
    bint(TotalSupply)
  )

  msg.reply({
    Action = "Price",
    Price = tostring(returnPrice)
  })
end

return mod
