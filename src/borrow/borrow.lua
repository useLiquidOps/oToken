local assertions = require ".utils.assertions"
local oracle = require ".liquidations.oracle"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.borrow(msg)
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

  -- the wallet that will borrow the tokens
  local account = msg.From

  -- get local collateralization first, so in case it is high enough,
  -- we don't even need to reach out to the friend processes to ensure
  -- collateralization
  local localCapacity = position.getLocalBorrowCapacity(account)
  local localUsedCapacity = position.getLocalUsedCapacity(account)

  -- if the loan wouldn't have enough collateral locally
  -- we check the global collateralization
  if not bint.ult(localUsedCapacity, localCapacity) or not bint.ule(quantity, localCapacity - localUsedCapacity) then
    -- get position data
    local capacity, usedCapacity = position.getGlobalCollateralization(
      account,
      msg.Timestamp
    )

    -- get borrow value in USD
    -- we request this after the collateralization, because
    -- in this case the oracle might not have to sync the price
    local borrowValue = oracle.getPrice(msg.Timestamp, false, {
      ticker = CollateralTicker,
      quantity = quantity,
      denomination = WrappedDenomination
    })

    -- make sure the user is allowed to borrow
    assert(bint.ult(usedCapacity, capacity), "Borrow balance is too high")
    assert(bint.ule(borrowValue, capacity - usedCapacity), "Not enough collateral for this borrow")
  end

  -- add loan
  Loans[account] = tostring(bint(Loans[account] or 0) + quantity)
  Available = tostring(available - quantity)
  Lent = tostring(bint(Lent) + quantity)

  -- send out the tokens
  ao.send({
    Target = Token,
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

return mod
