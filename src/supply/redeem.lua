local delegation = require ".supply.delegation"
local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)
local rate = require ".supply.rate"

---@type HandlerWithOracle
local function redeem(msg, _, oracle)
  -- check if the interaction is enabled
  assert(EnabledInteractions.redeem, "Redeeming is currently disabled")

  -- the wallet that is burning the tokens
  local sender = msg.From

  -- get position data
  local pos = position.globalPosition(sender, oracle)

  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid redeem quantity"
  )

  -- amount of tokens to burn
  local quantity = bint(msg.Tags.Quantity)

  -- oToken wallet balance for sender
  local walletBalance = bint(Balances[sender] or "0")

  -- check if the user has enough tokens to burn
  assert(
    bint.ule(quantity, walletBalance),
    "Not enough tokens to burn for this wallet"
  )

  -- total tokens pooled
  local availableTokens = bint(Cash)
  local totalSupply = bint(TotalSupply)

  -- calculate amount of tokens to be sent out
  local rewardQty = precision.toNativePrecision(
    rate.getUnderlyingWorth(quantity),
    "rounddown"
  )

  -- now we scale back up, because the actual removed
  -- quantity will be rounded down - thus we need to
  -- subtract that value
  local rewardQtyScaled = precision.toInternalPrecision(rewardQty)

  -- validate value limit
  assert(
    bint.ule(rewardQtyScaled, bint(ValueLimit)),
    "Redeem return quantity is above the allowed limit"
  )

  -- make sure there is enough tokens available to redeem for
  assert(
    bint.ult(rewardQtyScaled, availableTokens - bint(Reserves)),
    "Not enough available tokens to redeem for"
  )

  -- calculate how much capacity the removed reward tokens (collateral)
  -- worth, then calculate the USD value of that capacity
  -- important: this is in native precision
  local removedCapacityValue = oracle.getValue(
    -- get the capacity that will be removed
    bint.udiv(
      rewardQty * bint(CollateralFactor),
      bint(100)
    ),
    CollateralTicker
  )

  -- do not allow reserved collateral to be burned
  assert(
    assertions.isCollateralizedWithout(removedCapacityValue, pos),
    "Redeem value is too high and requires higher collateralization"
  )

  -- run delegation
  delegation.delegate(msg)

  -- update stored quantities (balance, available, total supply)
  Balances[sender] = tostring(walletBalance - quantity)
  Cash = tostring(availableTokens - rewardQtyScaled)
  TotalSupply = tostring(totalSupply - quantity)

  -- transfer
  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = tostring(rewardQty),
    Recipient = sender
  })

  msg.reply({
    Action = "Redeem-Confirmation",
    ["Earned-Quantity"] = tostring(rewardQty),
    ["Burned-Quantity"] = tostring(quantity)
  })
end

return redeem
