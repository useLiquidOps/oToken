local json = require "json"

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

-- Filter out expired addresses from the cooldown list
---@type HandlerFunction
function mod.sync(msg)
  -- filter addresses to remove
  ---@type string[]
  local expired = {}

  for addr, cooldown in pairs(Cooldowns) do
    if cooldown <= msg["Block-Height"] then
      table.insert(expired, addr)
    end
  end

  -- remove
  for _, address in ipairs(expired) do
    expired[address] = nil
  end
end

-- Cooldown middleware/gate that rejects 
-- interactions if the user is on cooldown
---@type HandlerFunction
function mod.gate(msg)
  -- user interacting with the protocol
  local sender = msg.From

  -- if this was a transfer, the sender needs to be updated
  if msg.Tags.Action == "Credit-Notice" then
    sender = msg.Tags.Sender
  end

  -- validate that the user cooldown is over
  assert(
    (Cooldowns[sender] or 0) <= msg["Block-Height"],
    "User is on a cooldown"
  )

  -- add user cooldown
  Cooldowns[sender] = msg["Block-Height"] + CooldownPeriod
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

-- List all users on cooldown
---@type HandlerFunction
function mod.list(msg)
  msg.reply({
    ["Cooldown-Period"] = tostring(CooldownPeriod),
    Data = next(Cooldowns) ~= nil and json.encode(Cooldowns) or "{}"
  })
end

return mod
