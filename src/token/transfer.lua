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
  local walletBalance = bint(Balances[msg.From] or 0)

  if bint.ule(quantity, walletBalance) then
    -- TODO: can the user transfer an loToken if they have a borrow ?????
    -- they shouldn't be able to, since the collateral is lost, and the system cannot liquidate

    -- update balances
    Balances[target] = tostring(bint(Balances[target] or 0) + quantity)
    Balances[msg.From] = tostring(walletBalance - quantity)

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

      msg.reply(debitNotice)
      ao.send(creditNotice)
    end
  else
    msg.reply({
      Action = "Transfer-Error",
      ["Message-Id"] = msg.Id,
      Error = "Insufficient Balance!"
    })
  end
end

return transfer
