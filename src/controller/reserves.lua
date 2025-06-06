local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)

local mod = {}

-- Allows withdrawing the tokens in the reserves from the controller
-- Note: reserved for future use in a governance model
---@type HandlerFunction
function mod.withdraw(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid withdraw quantity"
  )

  -- amount of tokens to withdraw
  local rawQuantity = bint(msg.Tags.Quantity)
  local quantity = precision.toInternalPrecision(rawQuantity)
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
    Quantity = tostring(rawQuantity),
    Recipient = msg.From
  })

  -- reply
  msg.reply({
    ["Total-Reserves"] = precision.formatInternalAsNative(Reserves, "roundup")
  })
end

-- Allows deploying the tokens from the reserves into the pool by the controller
-- Note: reserved for future use in a governance model
---@type HandlerFunction
function mod.deploy(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid deploy quantity"
  )

  -- amount of tokens to deploy
  local rawQuantity = bint(msg.Tags.Quantity)
  local quantity = precision.toInternalPrecision(rawQuantity)
  local reserves = bint(Reserves)

  -- check if there are enough tokens to deploy
  assert(
    bint.ule(quantity, reserves),
    "Not enough tokens available to deploy"
  )

  -- update reserves and cash
  Reserves = tostring(reserves - quantity)
  Cash = tostring(bint(Cash) + quantity)

  -- reply
  msg.reply({
    ["Total-Reserves"] = precision.formatInternalAsNative(Reserves, "roundup"),
    Cash = precision.formatInternalAsNative(Cash, "roundup")
  })
end

return mod
