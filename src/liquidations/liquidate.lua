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
  local target = msg.Tags["X-Liquidation-Target"]

  -- check if a loan can be repaid for the target
  assert(
    repay.canRepay(target, msg.Timestamp),
    "Cannot liquidate a loan for this user"
  )

  -- only the exact amount is allowed to be repaid
  assert(
    repay.canRepayExact(target, quantity),
    "The user has less tokens loaned than repaid"
  )

  -- call the collateral process to transfer out the reward
  local liquidatePos = ao.send({
    Target = msg.Tags["X-Reward-Market"],
    Action = "Liquidate-Position",
    Quantity = msg.Tags["X-Reward-Quantity"],
    Liquidator = liquidator,
    ["Liquidation-Target"] = target
  }).receive()

  -- check result, error if the position liquidation failed
  assert(
    not liquidatePos.Tags.Error and liquidatePos.Tags.Action == "Liquidate-Position-Confirmation",
    "Failed to liquidate position: " .. (liquidatePos.Tags.Error or "unknown error")
  )

  -- repay the loan
  -- execute repay
  local refundQty, actualRepaidQty = repay.repayToPool(
    target,
    quantity
  )

  -- refund if needed
  -- (this should never happen, because we only allow
  -- the exact quantity to be repaid)
  if not bint.eq(refundQty, bint.zero()) then
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = tostring(refundQty),
      Recipient = liquidator
    })
  end

  -- reply to the controller
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Liquidate-Borrow-Confirmation",
    ["Liquidated-Quantity"] = tostring(actualRepaidQty),
    Liquidator = liquidator,
    ["Liquidation-Target"] = target,
    ["Liquidation-Reference"] = msg.Tags["X-Liquidation-Reference"]
  })
end

-- Refunds tokens in case a borrow liquidation failed
---@param msg Message
---@param _ Message
---@param err unknown
function mod.refund(msg, _, err)
  local prettyError, rawError = utils.prettyError(err)
  local liquidator = msg.Tags["X-Liquidator"]

  -- refund
  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = liquidator
  })

  -- reply to the controller with an error
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Liquidate-Borrow-Error",
    Error = prettyError,
    ["Raw-Error"] = rawError,
    ["Liquidation-Reference"] = msg.Tags["X-Liquidation-Reference"]
  })
end

-- Transfers out the position to the liquidator
-- (reverse redeem)
---@type HandlerFunction
function mod.liquidatePosition(msg)
  -- check if the message is coming from a friend process
  assert(
    utils.includes(msg.From, Friends),
    "Only a friend process is authorized to call this function"
  )

  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid quantity"
  )

  -- amount of tokens to transfer out
  local quantity = bint(msg.Tags.Quantity)

  -- liquidator wallet
  local liquidator = msg.Tags.Liquidator

  assert(
    assertions.isAddress(liquidator),
    "Invalid liquidator address"
  )

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

  -- transfer to the liquidator
  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = tostring(quantity),
    Recipient = liquidator
  })

  -- reply to the controller
  msg.reply({
    Action = "Liquidate-Position-Confirmation",
    ["Liquidated-Position-Quantity"] = tostring(qtyValueInoToken)
  })
end

return mod
