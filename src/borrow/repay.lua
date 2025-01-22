local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local repay = {}

---@type HandlerFunction
function repay.handler(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid incoming transfer quantity"
  )

  -- quantity of tokens supplied
  local quantity = bint(msg.Tags.Quantity)

  -- allow repaying on behalf of someone else
  local target = msg.Tags["X-On-Behalf"] or msg.Tags.Sender

  -- check if a loan can be repaid for the target
  assert(
    repay.canRepay(target, msg.Timestamp),
    "Cannot repay a loan for this user"
  )

  -- execute repay
  local refundQty, actualRepaidQty = repay.repayToPool(
    target,
    quantity
  )

  -- refund the sender, if necessary
  if not bint.eq(refundQty, bint.zero()) then
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
    ["Refund-Quantity"] = tostring(refundQty)
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
  local prettyError, rawError = utils.prettyError(err)

  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender
  })
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Repay-Error",
    Error = prettyError,
    ["Raw-Error"] = rawError,
    ["Refund-Quantity"] = msg.Tags.Quantity
  })
end

-- Check if a repay can be executed with the given params.
-- This should be called before repay.repayToPool()
---@param target string Target to repay the loan for
---@param timestamp number Message timestamp
function repay.canRepay(target, timestamp)
  if not assertions.isAddress(target) then return false end

  -- fixup interest
  if not Interests[target] then
    Interests[target] = { value = "0", updated = timestamp }
  end

  local zero = bint.zero()

  return bint.ult(zero, bint(Loans[target] or "0")) or bint.ult(zero, bint(Interests[target].value))
end

-- Check if the exact provided quantity can be repaid
-- This should only be called after repay.canRepay()
---@param target string Target to repay the loan for
---@param quantity Bint Amount of tokens to be repaid
function repay.canRepayExact(target, quantity)
  -- borrow & interest balances for the target
  local borrowBalance = bint(Loans[target] or "0")
  local interestBalance = bint(Interests[target].value)

  return bint.ule(
    quantity,
    borrowBalance + interestBalance
  )
end

-- This function executes a repay. This is used both
-- in the actual repay handler, as well as the borrow
-- liquidation
-- It returns the amount of tokens that need to be
-- refunded and the amount of tokens repaid
-- Make sure to call repay.canRepay() with the same
-- params before calling this function
---@param target string Target to repay the loan for
---@param quantity Bint Amount of tokens to be repaid
function repay.repayToPool(target, quantity)
  -- borrow & interest balances for the target
  local borrowBalance = bint(Loans[target] or "0")
  local interestBalance = bint(Interests[target].value)

  local zero = bint.zero()

  -- refund quantity, in case the user overpaid
  local refundQty = zero

  -- first we repay the interests
  --
  -- in case the quantity is less than or equal to the
  -- outstanding interest, we just deduct from the interest
  if bint.ule(quantity, interestBalance) then
    Interests[target].value = tostring(interestBalance - quantity)
  else
    -- the quantity is more than the outstanding interest,
    -- so we reset the owned interest quantity and calculate
    -- the remainder of the repay interaction
    local remainingQty = quantity - interestBalance
    Interests[target].value = "0"

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

  return refundQty, actualRepaidQty
end

return repay
