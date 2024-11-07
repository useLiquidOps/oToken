local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)
local repay = require ".borrow.repay"
local utils = require ".utils.utils"

local mod = {}

-- Accepts the tokens paid for the liquidation by the liquidator
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
---@type HandlerFunction
function mod.liquidatePosition(msg)
  
end

return mod
