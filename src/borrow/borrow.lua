local assertions = require ".utils.assertions"
local Oracle = require ".liquidations.oracle"
local interests = require ".borrow.interest"
local position = require ".borrow.position"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function borrow(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid borrow quantity"
  )

  -- amount of tokens to borrow
  local quantity = bint(msg.Tags.Quantity)

  -- init oracle for the collateral token
  local oracle = Oracle:new{ [CollateralTicker] = CollateralDenomination }

  -- check if there are enough tokens available
  local cash = bint(Cash)

  -- we check if the quantity is less (and not less than equal) than
  -- the amount of tokens available to be lent so the interest ratio
  -- is never broken
  assert(bint.ult(quantity, cash), "Not enough tokens available to be lent")

  -- validate value limit
  assert(
    bint.ule(quantity, bint(ValueLimit)),
    "Borrow quantity is above the allowed limit"
  )

  -- calculate the max borrow amount (borrow capacity)
  local lent = bint(TotalBorrows)

  -- the wallet that will borrow the tokens
  local account = msg.From

  -- get borrow value in USD
  -- we request this after the collateralization, because
  -- in this case the oracle might not have to sync the price
  local borrowValue = oracle:getValue(quantity, CollateralTicker)

  -- get position data
  local pos = position.globalPosition(account)

  -- make sure the user is allowed to borrow
  assert(
    assertions.isCollateralized(borrowValue, pos),
    "Not enough collateral for this borrow"
  )

  -- add initial interest date if the user has no interest balance
  if not Interests[account] then
    Interests[account] = {
      value = "0",
      updated = Timestamp
    }
  else
    -- if the user has an interest balance, we sync it before
    -- adding the loan, to avoid overcharging for the time
    -- between the last sync (when the "Borrow" action was
    -- received by the process) and the oracle response
    interests.updateInterest(
      account,
      Timestamp,
      interests.genHelperData()
    )
  end

  -- add loan
  Loans[account] = tostring(bint(Loans[account] or 0) + quantity)
  Cash = tostring(cash - quantity)
  TotalBorrows = tostring(lent + quantity)

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
