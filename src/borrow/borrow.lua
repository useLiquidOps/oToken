local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

---@type HandlerWithOracle
local function borrow(msg, _, oracle)
  -- the wallet that will borrow the tokens
  local account = msg.From

  -- verify quantity
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid borrow quantity"
  )

  -- get position data
  local pos = position.globalPosition(account, oracle)

  -- amount of tokens to borrow
  local rawQuantity = bint(msg.Tags.Quantity)
  local quantity = precision.toInternalPrecision(rawQuantity)

  -- check if there are enough tokens available
  local cash = bint(Cash)

  -- we check if the quantity is less (and not less than equal) than
  -- the amount of tokens available to be lent so the interest ratio
  -- is never broken
  assert(bint.ult(quantity, cash), "Not enough tokens available to be lent")

  -- also check that the reserves are not borrowed
  assert(
    bint.ule(bint(Reserves), cash - quantity),
    "This action would require borrowing from the reserves"
  )

  -- validate value limit
  assert(
    bint.ule(quantity, bint(ValueLimit)),
    "Borrow quantity is above the allowed limit"
  )

  -- calculate the max borrow amount (borrow capacity)
  local lent = bint(TotalBorrows)

  -- get borrow value in USD
  -- we request this after the collateralization, because
  -- in this case the oracle might not have to sync the price
  local borrowValue = oracle.getValue(rawQuantity, CollateralTicker)

  -- make sure the user is allowed to borrow
  assert(
    assertions.isCollateralizedWith(borrowValue, pos),
    "Not enough collateral for this borrow"
  )

  -- add loan
  Loans[account] = tostring(bint(Loans[account] or 0) + quantity)
  Cash = tostring(cash - quantity)
  TotalBorrows = tostring(lent + quantity)

  -- send out the tokens
  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = tostring(rawQuantity),
    Recipient = account
  })

  -- send confirmation
  msg.reply({
    Action = "Borrow-Confirmation",
    ["Borrowed-Quantity"] = tostring(rawQuantity)
  })
end

return borrow
