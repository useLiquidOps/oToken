local mod = {}

-- Initializes the cooldown map
---@type HandlerFunction
function mod.setup()
  -- Users - cooldown deadlines in block height
  ---@type table<string, number>
  Cooldowns = Cooldowns or {}

  -- Cooldown period in blocks
  CooldownPeriod = CooldownPeriod or tonumber(ao.env.Process.Tags["Cooldown-Period"]) or 0
end

-- Cooldown middleware/gate that rejects 
-- interactions if the user is on cooldown
---@type HandlerFunction
function mod.gate(msg)
  
end

-- Refunds the user and sends the cooldown error
-- if the user is on cooldown
---@param msg Message
function mod.refund(msg)
  -- if this was a transfer, we refund it and send the error to the sender
  if msg.Tags.Action == "Credit-Notice" then
    local sender = msg.Tags.Sender

    -- refund
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = sender
    })

    -- send error
    ao.send({
      Target = sender,
      Action = (msg.Tags["X-Action"] or "Unknown") .. "-Error",
      Error = "Sender is on cooldown for " .. (Cooldowns[sender] - msg["Block-Height"]) .. " more block(s)"
    })
  else
    -- just reply to the message with an error
    msg.reply({
      Action = (msg.Tags.Action or "Unknown") .. "-Error",
      Error = "Sender is on cooldown for " .. (Cooldowns[msg.From] - msg["Block-Height"]) .. " more block(s)"
    })
  end

  -- stop execution
  return "break"
end

return mod
