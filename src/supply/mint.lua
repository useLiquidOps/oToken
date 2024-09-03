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

  -- total tokens pooled and supply
  local availableTokens = bint(Available)
  local totalPooled = availableTokens + bint(Lent)
  local totalSupply = bint(TotalSupply)

  if not bint.eq(totalPooled, bint.zero()) then
    -- mint in proportion to the already supplied tokens
    mintQty = bint.udiv(
      totalSupply * quantity,
      totalPooled
    )
  end

  -- update stored quantities (balance, available, total supply)
  Balances[sender] = tostring(bint(Balances[sender] or 0) + mintQty)
  Available = tostring(availableTokens + quantity)
  TotalSupply = tostring(totalSupply + mintQty)

  -- TODO: maybe we could msg.reply, but the target of that would be
  -- the token process that sent the "Credit-Notice"
  -- we need to discuss with the ao team if the reply is actually forwarded
  -- to the original user/process who sent the transfer or if we need
  -- to add some custom tags that directly reply to that user
  -- (same applies to all "Credit-Notice" handlers)
  -- UPDATE: looking at the standard token code, this probably needs to be
  -- implemented in a separate PR (in the token blueprint)
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
