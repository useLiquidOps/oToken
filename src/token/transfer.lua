local assertions = require ".utils.assertions"
local oracle = require ".liquidations.oracle"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function transfer(msg)
  -- transfer target and sender
  local target = msg.Tags.Recipient or msg.Target
  local sender = msg.From

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

  -- get position data
  local capacity, usedCapacity = position.getGlobalCollateralization(sender)

  -- get the value of the tokens to be transferred in
  -- terms of the underlying asset and then get the price
  -- of that quantity
  local transferValue = oracle.getPrice({
    ticker = CollateralTicker,
    quantity = quantity,
    denomination = CollateralDenomination
  })

  -- check if a price was returned
  assert(transferValue[1] ~= nil, "No price returned from the oracle for the transfer value")

  -- do not allow reserved collateral to be transferred
  assert(
    bint.ule(transferValue[1].price, capacity - usedCapacity),
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
