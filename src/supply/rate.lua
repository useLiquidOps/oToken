local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function exchangeRate(msg)
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
  local totalPooled = bint(Cash) + bint(TotalBorrows)

  -- calculate price based on the underlying value of the total supply
  local returnPrice = quantity
  local totalSupply = bint(TotalSupply)

  -- price is one if there are no tokens supplied,
  -- otherwise calculate it
  if not bint.eq(totalSupply, bint.zero()) then
    returnPrice = bint.udiv(
      totalPooled * quantity,
      totalSupply
    )
  end

  msg.reply({
    Quantity = tostring(quantity),
    Price = tostring(returnPrice)
  })
end

return exchangeRate
