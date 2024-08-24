local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

---@param msg Message
local function transfer(msg)
  -- transfer target
  local target = msg.Tags.Recipient or msg.Target

  -- validate target and quantity
  assert(assertions.isAddress(target), "Invalid address")
  assert(target ~= msg.From, "Target cannot be the sender")
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid transfer quantity"
  )

  local quantity = bint(msg.Tags.Quantity)

  -- validate user balance
  assert(Balances[msg.From] ~= nil, "No balance for this user")
  assert(bint.ule(quantity, Balances[msg.From]), "Not enought tokens for this transfer")

  -- update balances
  Balances[target] = (Balances[target] or bint.zero()) + quantity
  Balances[msg.From] = Balances[msg.From] - quantity

  -- send notices about the transfer
  if not msg.Tags.Cast then
    local debitNotice = {
      Target = msg.From,
      Action = "Debit-Notice",
      Recipient = target,
      Quantity = tostring(quantity)
    }
    local creditNotice = {
      Target = target,
      Action = "Credit-Notice",
      Sender = msg.From,
      Quantity = tostring(quantity)
    }

    -- forwarded tags
    for tagName, tagValue in pairs(msg.Tags) do
      if string.sub(tagName, 1, 2) == "X-" then
        debitNotice[tagName] = tagValue
        creditNotice[tagName] = tagValue
      end
    end

    ao.send(debitNotice)
    ao.send(creditNotice)
  end
end

return transfer
