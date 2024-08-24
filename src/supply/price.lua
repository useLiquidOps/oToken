local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function price(msg)
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
  local totalPooled = Available + Lent

  -- calculate price based on the underlying value of the total supply
  local returnPrice = bint.udiv(
    totalPooled * quantity,
    TotalSupply
  )

  msg.reply({
    Action = "Price",
    Price = tostring(returnPrice)
  })
end

return price
