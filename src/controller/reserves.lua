local assertions = require ".utils.assertions"
local precision = require ".utils.precision"
local bint = require ".utils.bint"(1024)

local mod = {}

-- Allows deploying the tokens from the reserves into the pool by the controller
-- Note: reserved for future use in a governance model
---@type HandlerFunction
function mod.deploy(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid deploy quantity"
  )

  -- amount of tokens to deploy
  local quantity = precision.toInternalPrecision(
    bint(msg.Tags.Quantity)
  )

  -- cash available
  Cash = tostring(bint(Cash) + quantity)

  -- reply
  msg.reply({
    Cash = precision.formatInternalAsNative(Cash, "rounddown")
  })
end

return mod
