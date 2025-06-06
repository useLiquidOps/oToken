local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)

local mod = {}

-- Calculate how much the provided oToken quantity is worth
-- in terms of the underlying asset (collateral). 
-- Important: The returned value uses the internal
-- collateral precision
---@param qty Bint The quantity to get the value for
function mod.getUnderlyingWorth(qty)
  -- parse pool values
  local totalPooled = bint(Cash) + bint(TotalBorrows) - bint(Reserves)
  local totalSupply = bint(TotalSupply)

  -- if the total supply is 0, then the
  -- conversion rate is 1:1
  if bint.eq(totalSupply, bint.zero()) then
    return precision.toInternalPrecision(qty)
  end

  -- if the total pooled and the total supply is not
  -- the same, then the reward qty will be higher
  -- than the burn qty, because there was already
  -- some interest coming in
  return bint.udiv(
    totalPooled * qty,
    totalSupply
  )
end

---@type HandlerFunction
function mod.exchangeRate(msg)
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

  -- calculate value based on the underlying value of the total supply
  local returnValue = precision.toNativePrecision(
    mod.getUnderlyingWorth(quantity),
    "rounddown"
  )

  msg.reply({
    Quantity = tostring(quantity),
    Value = tostring(returnValue)
  })
end

return mod
