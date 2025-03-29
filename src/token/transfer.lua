local assertions = require ".utils.assertions"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)
local rate = require ".supply.rate"

---@type HandlerWithOracle
local function transfer(msg, _, oracle)
  -- transfer target and sender
  local target = msg.Tags.Recipient or msg.Target
  local sender = msg.From

  -- get position data
  local pos = position.globalPosition(sender, oracle)

  -- validate target and quantity
  assert(assertions.isAddress(target), "Invalid address")
  assert(target ~= sender, "Target cannot be the sender")
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid transfer quantity"
  )

  local quantity = bint(msg.Tags.Quantity)
  local walletBalance = bint(Balances[sender] or 0)

  -- check if the user has enough tokens
  assert(bint.ule(quantity, walletBalance), "Insufficient balance")

  -- calculate how much collateral the transferred tokens are worth
  local collateralValue = rate.getUnderlyingWorth(quantity)

  -- calculate how much capacity the transferred underlying tokens
  -- (collateral) worth, then calculate the USD value of that capacity
  local removedCapacityValue = oracle.getValue(
    -- get the capacity that will be removed
    bint.udiv(
      collateralValue * bint(CollateralFactor),
      bint(100)
    ),
    CollateralTicker
  )

  -- do not allow reserved collateral to be transferred
  assert(
    assertions.isCollateralizedWithout(removedCapacityValue, pos),
    "Transfer value is too high and requires higher collateralization"
  )

  -- update balances
  Balances[target] = tostring(bint(Balances[target] or 0) + quantity)
  Balances[sender] = tostring(walletBalance - quantity)

  -- send notices about the transfer
  if not msg.Tags.Cast then
    local debitNotice = {
      Action = "Debit-Notice",
      Recipient = target,
      Quantity = tostring(quantity)
    }
    local creditNotice = {
      Target = target,
      Action = "Credit-Notice",
      Sender = sender,
      Quantity = tostring(quantity)
    }

    -- forwarded tags
    for tagName, tagValue in pairs(msg.Tags) do
      if string.sub(tagName, 1, 2) == "X-" then
        debitNotice[tagName] = tagValue
        creditNotice[tagName] = tagValue
      end
    end

    msg.reply(debitNotice)
    ao.send(creditNotice)
  end
end

return transfer
