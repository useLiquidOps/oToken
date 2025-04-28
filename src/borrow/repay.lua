local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local interest = require ".borrow.interest"
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
    repay.canRepay(target),
    "Cannot repay a loan for this user"
  )

  -- execute repay
  local refundQty, actualRepaidQty = repay.repayToPool(target, quantity)

  -- refund the sender, if necessary
  if not bint.eq(refundQty, bint.zero()) then
    ao.send({
      Target = CollateralID,
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
  local sender = msg.Tags.Sender

  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = sender
  })

  if assertions.isAddress(sender) then
    ao.send({
      Target = sender,
      Action = "Repay-Error",
      Error = prettyError,
      ["Raw-Error"] = rawError,
      ["Refund-Quantity"] = msg.Tags.Quantity
    })
  end
end

-- Check if a repay can be executed with the given params.
-- This should be called before repay.repayToPool()
---@param target string Target to repay the loan for
function repay.canRepay(target)
  if not assertions.isAddress(target) then return false end
  return bint.ult(bint.zero(), bint(Loans[target] or "0"))
end

-- Check if the exact provided quantity can be repaid
-- This should only be called after repay.canRepay()
---@param target string Target to repay the loan for
---@param quantity Bint Amount of tokens to be repaid
function repay.canRepayExact(target, quantity)
  -- accrue interest for the user and get the borrow balance
  -- in native precision, rounded upwards
  local borrowBalance = precision.toNativePrecision(
    interest.accrueInterestForUser(target),
    "roundup"
  )
  return bint.ule(quantity, borrowBalance)
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
---@return Bint, Bint
function repay.repayToPool(target, quantity)
  -- accrue interest for the user and get the borrow balance
  -- in native precision, rounded upwards
  local internalBorrowBalance = interest.accrueInterestForUser(target)
  local borrowBalance = precision.toNativePrecision(internalBorrowBalance, "roundup")
  local zero = bint.zero()

  -- refund quantity, in case the user overpaid
  local refundQty = zero

  -- if the outstanding loan is less than the repaid
  -- quantity, the loan is reset and the user is
  -- refunded the remainder
  if bint.ule(borrowBalance, quantity) then
    Loans[target] = nil
    refundQty = quantity - borrowBalance
  else
    -- the outstanding loan is more than or equal to the
    -- remaining repay quantity, so we just deduct it
    --
    -- this has to be done in the internal precision
    Loans[target] = tostring(internalBorrowBalance - precision.toInternalPrecision(quantity))
  end

  -- the actual quantity repaid (needed in case we need to refund the user)
  local actualRepaidQty = quantity - refundQty

  -- finally, we add the repaid amount back to the pool (minus the reserve amount if needed)
  Cash = tostring(bint(Cash) + precision.toInternalPrecision(actualRepaidQty))
  TotalBorrows = tostring(bint(TotalBorrows) - precision.toInternalPrecision(actualRepaidQty))

  return refundQty, actualRepaidQty
end

return repay
