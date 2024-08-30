local assertions = require ".utils.assertions"
local oracle = require ".liquidations.oracle"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.borrow(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid borrow quantity"
  )

  -- amount of tokens to borrow
  local quantity = bint(msg.Tags.Quantity)

  -- get borrow capacity
  local capacity = position.getLocalBorrowCapacity(msg.From)

  -- if the borrow capacity is not enough, 
  -- we need to check the local collateralization
  -- of the other loTokens
  if bint.ult(capacity, quantity) then
    -- get the USD value of the local capacity
    -- (other tokens will return the same)
    local localCapacityUSD = oracle.getUnderlyingPrice(capacity)

    -- TODO: get capacity from other loTokens

    -- TODO: assert for enough capacity
  end

  -- TODO: add loan

  -- TODO: send out the tokens
end

return mod
