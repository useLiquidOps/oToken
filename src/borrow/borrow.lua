local assertions = require ".utils.assertions"
local oracle = require ".liquidations.oracle"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

---@type HandlerFunction
local function borrow(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid borrow quantity"
  )

  -- amount of tokens to borrow
  local quantity = bint(msg.Tags.Quantity)

  -- check if there are enough tokens available
  local available = bint(Available)

  -- we check if the quantity is less (and not less than equal) than
  -- the amount of tokens available to be lent so the interest ratio
  -- is never broken
  assert(bint.ult(quantity, available), "Not enough tokens available to be lent")

  -- multiply the collateral factor by 1000
  -- we do this, so that we can calculate with more precise
  -- ratios below, while using bigintegers
  -- later the final result needs to be multiplied by
  -- 1000 as well, to get the actual result
  local collateralFactorWhole, ratioMul = utils.floatBintRepresentation(CollateralFactor)
  local lent = bint(Lent)

  -- check if the collateral-factor is not reached
  -- total tokens: av + le
  -- max allowed: (av + le) / cf
  assert(
    bint.ule(quantity, bint.udiv(
      (available + lent) * ratioMul,
      collateralFactorWhole
    )),
    "This quantity would damage the required collateral factor"
  )

  -- the wallet that will borrow the tokens
  local account = msg.From

  -- get position data
  local capacity, usedCapacity = position.getGlobalCollateralization(
    account,
    msg.Timestamp
  )

  -- get borrow value in USD
  -- we request this after the collateralization, because
  -- in this case the oracle might not have to sync the price
  local borrowValue = oracle.getPrice(msg.Timestamp, {
    ticker = CollateralTicker,
    quantity = quantity,
    denomination = CollateralDenomination
  })

  -- make sure the oracle returned a price
  assert(borrowValue[1] ~= nil, "No price returned from the oracle for the borrow quantity")

  -- make sure the user is allowed to borrow
  assert(bint.ult(usedCapacity, capacity), "Borrow balance is too high")
  assert(
    bint.ule(borrowValue[1].price, capacity - usedCapacity),
    "Not enough collateral for this borrow"
  )

  -- add loan
  Loans[account] = tostring(bint(Loans[account] or 0) + quantity)
  Available = tostring(available - quantity)
  Lent = tostring(lent + quantity)

  -- send out the tokens
  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = tostring(quantity),
    Recipient = account
  })

  -- send confirmation
  msg.reply({
    Action = "Borrow-Confirmation",
    ["Borrowed-Quantity"] = tostring(quantity)
  })
end

return borrow
