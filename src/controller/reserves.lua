local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mod = {}

---@type HandlerFunction
function mod.withdraw(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid borrow quantity"
  )

  -- amount of tokens to withdraw
  local quantity = bint(msg.Tags.Quantity)
  local reserves = bint(Reserves)

  -- check if there are enough tokens to withdraw
  assert(
    bint.ule(quantity, reserves),
    "Not enough tokens available to withdraw"
  )

  -- update reserves
  Reserves = tostring(reserves - quantity)

  -- transfer tokens
  ao.send({
    Target = CollateralID,
    Action = "Transfer",
    Quantity = tostring(quantity),
    Recipient = msg.From
  })

  -- reply
  msg.reply({
    ["Withdrawn-Quantity"] = msg.Tags.Quantity,
    ["Total-Reserves"] = Reserves
  })
end

---@type HandlerFunction
function mod.deploy(msg)
  
end

return mod
