local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local repay = {}

---@type HandlerFunction
function repay.handler(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid incoming transfer quantity"
  )

  -- quantity of tokens supplied
  local quantity = bint(msg.Tags.Quantity)

  -- repay on behalf of someone else
  local target = msg.Tags["X-On-Behalf"] or msg.Tags.Sender

  assert(
    assertions.isAddress(target),
    "Invalid repay target address"
  )

  -- borrow & interest balances for the target
  local borrowBalance = bint(Loans[target] or "0")
  local interestBalance = bint(Interests[target] or "0")

  local zero = bint.zero()

  assert(
    bint.ult(zero, borrowBalance) or bint.ult(zero, interestBalance),
    "No outstanding loans or interest to repay for " .. target
  )

  -- refund quantity, in case the user overpaid
  local refundQty = zero

  -- first we repay the interests
  --
  -- in case the quantity is less than or equal to the
  -- outstanding interest, we just deduct from the interest
  if bint.ule(quantity, interestBalance) then
    Interests[target] = tostring(interestBalance - quantity)
  else
    -- the quantity is more than the outstanding interest,
    -- so we reset the owned interest quantity and calculate
    -- the remainder of the repay interaction
    local remainingQty = quantity - interestBalance
    Interests[target] = "0"

    -- then if there are any tokens left, we repay the borrow
    --
    -- if the outstanding loan is less than the remaining
    -- quantity after paying the interests, we need to reset
    -- the quantity owned by the target and refund the remainder
    if bint.ult(borrowBalance, remainingQty) then
      Loans[target] = "0"
      refundQty = remainingQty - borrowBalance
    else
      -- the outstanding loan is more than or equal to the
      -- remaining repay quantity, so we just deduct it
      Loans[target] = tostring(borrowBalance - remainingQty)
    end
  end

  -- the actual quantity repaid (needed in case we need to refund the user)
  local actualRepaidQty = quantity - refundQty

  -- finally, we add the repaid amount back to the pool
  Available = tostring(bint(Available) + actualRepaidQty)
  Lent = tostring(bint(Lent) - actualRepaidQty)

  -- refund the sender, if necessary
  if not bint.eq(refundQty, zero) then
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = tostring(refundQty),
      Recipient = msg.Tags.Sender
    })
  end

  -- notify the sender
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Repay-Confirmation",
    ["Repaid-Quantity"] = tostring(actualRepaidQty),
    ["Refunded-Quantity"] = tostring(refundQty)
  })

  -- if this was paid on behalf of someone else
  -- we will also notify them
  if target ~= msg.Tags.Sender then
    ao.send({
      Target = target,
      Action = "Repay-Confirmation",
      ["Repaid-Quantity"] = tostring(actualRepaidQty),
      ["Repaid-By"] = msg.Tags.Sender
    })
  end
end

---@param msg Message
---@param _ Message
---@param err unknown
function repay.error(msg, _, err)
  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender
  })
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Repay-Error",
    Error = tostring(err),
    ["Refund-Quantity"] = msg.Tags.Quantity
  })
end

return repay
