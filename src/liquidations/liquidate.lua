local utils = require ".utils.utils"

local mod = {}

-- Accepts the tokens paid for the liquidation by the liquidator
---@type HandlerFunction
function mod.liquidateBorrow(msg)

end

-- Refunds tokens in case a borrow liquidation failed
---@param msg Message
---@param _ Message
---@param err unknown
function mod.refund(msg, _, err)
  local prettyError, rawError = utils.prettyError(err)

  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender
  })
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Liquidate-Borrow-Error",
    Error = prettyError,
    ["Raw-Error"] = rawError,
    ["Refund-Quantity"] = msg.Tags.Quantity
  })
end

-- Transfers out the position to the liquidator
---@type HandlerFunction
function mod.liquidatePosition(msg)
  
end

return mod
