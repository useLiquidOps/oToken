local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

local mint = {}

---@type HandlerFunction
function mint.handler(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid incoming transfer quantity"
  )

  -- quantity of tokens supplied
  local quantity = bint(msg.Tags.Quantity)

  -- transfer sender
  local sender = msg.Tags.Sender

  -- amount of loTokens to be minted
  local mintQty = quantity

  -- total tokens pooled
  local totalPooled = Available + Lent

  if not bint.eq(totalPooled, bint.zero()) then
    -- mint in proportion to the already supplied tokens
    mintQty = bint.udiv(
      TotalSupply * quantity,
      totalPooled
    )
  end

  -- update stored quantities (balance, available, total supply)
  Balances[sender] = (Balances[sender] or bint.zero()) + mintQty
  Available = (Available or bint.zero()) + quantity
  TotalSupply = (TotalSupply or bint.zero()) + mintQty

  ao.send({
    Target = sender,
    Action = "Mint-Confirmation",
    ["Mint-Quantity"] = tostring(mintQty),
    ["Supplied-Quantity"] = msg.Tags.Quantity
  })
end

---@param msg Message
---@param _ Message
---@param err unknown
function mint.error(msg, _, err)
  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender
  })
  ao.send({
    Target = msg.Tags.Sender,
    Action = "Mint-Error",
    Error = tostring(err),
    ["Refund-Quantity"] = msg.Tags.Quantity
  })
end

return mint
