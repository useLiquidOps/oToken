local assertions = require ".utils.assertions"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

---@type HandlerWithOracle
local function redeem(msg, _, oracle)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid redeem quantity"
  )

  -- amount of tokens to burn
  local quantity = bint(msg.Tags.Quantity)

  -- the wallet that is burning the tokens
  local sender = msg.From

  -- oToken wallet balance for sender
  local walletBalance = bint(Balances[sender] or "0")

  -- check if the user has enough tokens to burn
  assert(
    bint.ule(quantity, walletBalance),
    "Not enough tokens to burn for this wallet"
  )

  -- amount of tokens to be sent out
  local rewardQty = quantity

  -- total tokens pooled
  local availableTokens = bint(Cash)
  local totalPooled = availableTokens + bint(TotalBorrows)
  local totalSupply = bint(TotalSupply)

  -- if the total pooled and the total supply is not
  -- the same, then the reward qty will be higher
  -- than the burn qty, because there was already
  -- some interest coming in
  if not bint.eq(totalPooled, totalSupply) then
    rewardQty = bint.udiv(
      totalPooled * quantity,
      totalSupply
    )
  end

  -- validate value limit
  assert(
    bint.ule(rewardQty, bint(ValueLimit)),
    "Redeem return quantity is above the allowed limit"
  )

  -- make sure there is enough tokens available to redeem for
  assert(
    bint.ult(rewardQty, availableTokens),
    "Not enough available tokens to redeem for"
  )

  -- get the value of the tokens to be burned in
  -- terms of the underlying asset and then get the price
  -- of that quantity
  local burnValue = oracle.getValue(quantity, CollateralTicker, CollateralDenomination)

  -- get position data
  local pos = position.globalPosition(sender, oracle)

  -- do not allow reserved collateral to be burned
  assert(
    assertions.isCollateralized(burnValue, pos),
    "Redeem value is too high and requires higher collateralization"
  )

  -- update stored quantities (balance, available, total supply)
  Balances[sender] = tostring(walletBalance - quantity)
  Cash = tostring(availableTokens - rewardQty)
  TotalSupply = tostring(totalSupply - quantity)

  msg.reply({
    Action = "Redeem-Confirmation",
    ["Earned-Quantity"] = tostring(rewardQty),
    ["Burned-Quantity"] = tostring(quantity)
  })
end

return redeem
