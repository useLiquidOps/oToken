local mod = {}

-- Check if a user is queued in the controller. This could be
-- due to an ongoing operation involving the collateral or
-- a cooldown
---@param address string User address
---@return boolean
function mod.isQueued(address)
  -- check queue
  ---@type Message
  local res = ao.send({
    Target = ao.env.Process.Owner,
    Action = "Check-Queue-For",
    User = address
  }).receive(nil, Block + 1)

  return res.Tags["In-Queue"] == "true"
end

-- Add or remove a user from the queue in the controller
---@param address string User address
---@param queued boolean User queue status
---@return boolean
function mod.setQueued(address, queued)
  -- try to update the queue
  ---@type Message
  local res = ao.send({
    Target = ao.env.Process.Owner,
    Action = queued and "Add-To-Queue" or "Remove-From-Queue",
    User = address
  }).receive(nil, Block + 1)

  return res.Tags[queued and "Queued-User" or "Unqueued-User"] == address
end

-- Ensures that queued users are rejected and refunded
---@type HandlerFunction
function mod.queueGuard(msg)
  -- default sender of the interaction is the message sender
  local sender = msg.From
  local isCreditNotice = msg.Tags.Action == "Credit-Notice"

  -- if the message is a credit notice, update the sender
  if isCreditNotice then
    sender = msg.Tags.Sender
  end

  -- update and set queue
  local res = mod.setQueued(sender, true)

  -- if we weren't able to queue the user,
  -- then they have already been queued
  -- first, we refund the user
  if not res and isCreditNotice then
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = msg.Tags.Sender,
      ["X-Action"] = "Refund",
      ["X-Refund-Reason"] = "The sender is already queued for an operation"
    })
  end

  -- error if the user is already in the queue
  assert(res, "The sender is already queued for an operation")
end

return mod
