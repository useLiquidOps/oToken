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

  -- calculate value based on the underlying value of the total supply
  local returnValue = quantity
  local totalSupply = bint(TotalSupply)

  -- value is one if there are no tokens supplied,
  -- otherwise calculate it
  if not bint.eq(totalSupply, bint.zero()) then
    returnValue = bint.udiv(
      totalPooled * quantity,
      totalSupply
    )
  end

  msg.reply({
    Quantity = tostring(quantity),
    Value = tostring(returnValue)
  })
end

return exchangeRate
