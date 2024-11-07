local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)
local repay = require ".borrow.repay"
local utils = require ".utils.utils"

local mod = {}

-- Accepts the tokens paid for the liquidation by the liquidator
-- (similar functionality to repaying)
---@type HandlerFunction
function mod.liquidateBorrow(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid incoming transfer quantity"
  )

  -- quantity of tokens paid
  local quantity = bint(msg.Tags.Quantity)

  -- the liquidator
  local liquidator = msg.Tags["X-Liquidator"]

  -- liquidation tartget
  local target = msg.Tags["X-Target"]

  -- repay the loan
  -- execute repay
  local refundQty, actualRepaidQty = repay.repayToPool(
    target,
    quantity,
    msg.Timestamp
  )

  -- refund if needed
  local needsRefund = not bint.eq(refundQty, bint.zero())

  if needsRefund then
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = tostring(refundQty),
      Recipient = msg.Tags.Sender
    })
  end

  -- notify the liquidator
  ao.send({
    Target = liquidator,
    Action = "Liquidate-Borrow-Confirmation",
    ["Liquidated-Token"] = CollateralID,
    ["Liquidated-Quantity"] = tostring(actualRepaidQty),
    ["Refund-Quantity"] = tostring(refundQty),
    ["Liquidation-Target"] = target
  })

  -- notify the liquidated user
  ao.send({
    Target = target,
    Action = "Liquidation-Notice",
    ["Liquidated-Token"] = CollateralID,
    ["Liquidated-Quantity"] = tostring(actualRepaidQty),
    Liquidator = liquidator
  })

  -- reply to the controller
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Liquidate-Borrow-Confirmation",
    ["Liquidated-Quantity"] = tostring(actualRepaidQty),
    ["Refund-Quantity"] = msg.Tags.Quantity,
    Liquidator = msg.Tags["X-Liquidator"],
    ["Liquidation-Target"] = msg.Tags["X-Target"]
  })
end

-- Refunds tokens in case a borrow liquidation failed
---@param msg Message
---@param _ Message
---@param err unknown
function mod.refund(msg, _, err)
  local prettyError, rawError = utils.prettyError(err)
  local liquidator = msg.Tags["X-Liquidator"]

  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender
  })
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Liquidate-Borrow-Error",
    Error = prettyError,
    ["Raw-Error"] = rawError,
    ["Refund-Quantity"] = msg.Tags.Quantity,
    Liquidator = msg.Tags["X-Liquidator"],
    ["Liquidation-Target"] = msg.Tags["X-Target"]
  })

  if liquidator then
    ao.send({
      Target = liquidator,
      Action = "Liquidate-Borrow-Confirmation",
      ["Liquidated-Token"] = CollateralID,
      Error = prettyError,
      ["Raw-Error"] = rawError,
      ["Refund-Quantity"] = msg.Tags.Quantity,
      ["Liquidation-Target"] = msg.Tags["X-Target"]
    })
  end
end

-- Transfers out the position to the liquidator
-- (reverse redeem)
---@type HandlerFunction
function mod.liquidatePosition(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid quantity"
  )

  -- amount of tokens to transfer out
  local quantity = bint(msg.Tags.Quantity)

  -- liquidation target
  local target = msg.Tags["Liquidation-Target"]

  -- check if the user owns enough tokens for this transfer
  -- by checking the if the value of the supplied quantity
  -- in terms of the oToken is less than or equal to the
  -- amount of oTokens owned
  local balance = bint(Balances[target] or 0)

  assert(bint.eq(balance, bint.zero()), "Not enough tokens owned by the user to liquidate")

  -- helpers
  local totalSupply = bint(TotalSupply)
  local availableTokens = bint(Available)
  local totalPooled = availableTokens + bint(Lent)

  -- validate if there are enough available tokens
  assert(
    bint.ule(quantity, availableTokens),
    "Not enough tokens available to liquidate"
  )

  -- get supplied quantity value
  -- total supply is 100
  -- total pooled is 5
  -- 5 incoming = 100 oToken
  -- (total supply / total pooled) * incoming
  local qtyValueInoToken = bint.udiv(
    totalSupply * totalPooled,
    quantity
  )

  -- validate with oToken balance
  assert(
    bint.ule(qtyValueInoToken, balance),
    "The user owns less oTokens than the supplied quantity's worth"
  )

  -- liquidate position by updating the reserves, etc.
  Balances[target] = tostring(balance - qtyValueInoToken)
  Available = tostring(availableTokens - quantity)
  TotalSupply = tostring(totalSupply - qtyValueInoToken)

  -- TODO: notify, transfer
end

return mod
