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

  assert(
    assertions.isAddress(liquidator),
    "Invalid liquidator address"
  )

  -- liquidation tartget
  local target = msg.Tags["X-Liquidation-Target"]

  assert(
    assertions.isAddress(target),
    "Invalid liquidation target address"
  )

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

  -- validate reward market
  local rewardMarket = msg.Tags["X-Reward-Market"]

  assert(
    assertions.isAddress(rewardMarket),
    "Invalid reward market"
  )

  -- validate sender
  local sender = msg.Tags.Sender

  assert(
    assertions.isAddress(sender),
    "Invalid liquidation sender"
  )
  assert(
    assertions.isTokenQuantity(msg.Tags["X-Reward-Quantity"]),
    "Invalid reward quantity"
  )

  -- call the collateral process to transfer out the reward
  local liquidatePos = ao.send({
    Target = rewardMarket,
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
      Target = CollateralID,
      Action = "Transfer",
      Quantity = tostring(refundQty),
      Recipient = liquidator
    })
  end

  -- reply to the controller
  ao.send({
    Target = sender,
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
  local sender = msg.Tags.Sender

  -- refund
  if assertions.isTokenQuantity(msg.Tags.Quantity) then
    ao.send({
      Target = CollateralID,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = liquidator
    })
  end

  -- reply to the controller with an error
  if assertions.isAddress(sender) then
    ao.send({
      Target = sender,
      Action = "Liquidate-Borrow-Error",
      Error = prettyError,
      ["Raw-Error"] = rawError,
      ["Liquidation-Reference"] = msg.Tags["X-Liquidation-Reference"]
    })
  end
end

-- Transfers out the position to the liquidator
-- (reverse redeem)
---@type HandlerFunction
function mod.liquidatePosition(msg)
  -- check if the message is coming from a friend process
  assert(
    assertions.isFriend(msg.From),
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

  assert(
    assertions.isAddress(target),
    "Invalid liquidation target address"
  )

  -- check if the user owns enough tokens for this transfer
  -- by checking the if the value of the supplied quantity
  -- in terms of the oToken is less than or equal to the
  -- amount of oTokens owned
  local balance = bint(Balances[target] or 0)

  assert(
    bint.ult(bint.zero(), balance),
    "The liquidation target does not have collateral in this token"
  )

  -- helpers
  local totalSupply = bint(TotalSupply)
  local availableTokens = bint(Cash)
  local totalPooled = availableTokens + bint(TotalBorrows)

  -- validate if there are enough available tokens
  assert(
    bint.ule(quantity, availableTokens),
    "Not enough tokens available to liquidate"
  )

  -- get supplied quantity value
  -- (total supply / total pooled) * incoming
  local qtyValueInoToken = utils.udiv_roundup(
    totalSupply * quantity,
    totalPooled
  )

  -- validate with oToken balance
  assert(
    bint.ule(qtyValueInoToken, balance),
    "The liquidation target owns less oTokens than the supplied quantity's worth"
  )

  -- liquidate position by updating the oToken quantities, etc.
  Balances[target] = tostring(balance - qtyValueInoToken)
  Cash = tostring(availableTokens - quantity)
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
