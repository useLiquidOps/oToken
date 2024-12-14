local mod = {}

-- Add or remove a user from the queue in the controller
---@param address string User address
---@param queued boolean User queue status
---@return { receive: fun(): boolean; notifyOnFailedQueue: function }
function mod.setQueued(address, queued)
  -- try to update the queue
  local msg = ao.send({
    Target = ao.env.Process.Owner,
    Action = queued and "Add-To-Queue" or "Remove-From-Queue",
    User = address
  })

  -- helper function to get if the operation succeeded
  ---@param res Message Resulting message
  local function succeeded(res)
    return res.Tags[queued and "Queued-User" or "Unqueued-User"] == address
  end

  return {
    -- Wait for the response before continuing
    receive = function ()
      -- wait for response message
      local res = msg.receive(nil, Block + 1)

      -- get if the operation succeeded
      return succeeded(res)
    end,
    -- Notify the user that we could not unqueue them
    notifyOnFailedQueue = function ()
      msg.onReply(function (_msg)
        -- don't do anything if the operation succeeds
        if succeeded(_msg) then return end

        -- indicate failure
        ao.send({
          Target = address,
          Action = "Queue-Error",
          Error = "Failed to unqueue user " .. address
        })
      end)
    end
  }
end

-- Ensures that queued users are rejected and refunded
---@param msg Message Current message
function mod.queueGuard(msg)
  -- default sender of the interaction is the message sender
  local sender = msg.From
  local isCreditNotice = msg.Tags.Action == "Credit-Notice"

  -- if the message is a credit notice, update the sender
  if isCreditNotice then
    sender = msg.Tags.Sender
  end

  -- update and set queue
  local res = mod.setQueued(sender, true).receive()

  -- if we weren't able to queue the user,
  -- then they have already been queued
  -- (an operation is already in progress)
  if not res then
    msg.reply({
      Action = msg.Tags.Action .. "-Error",
      Error = "The sender is already queued for an operation"
    })

    -- first, we refund the user if the
    -- message resulted from a transfer
    if isCreditNotice then
      ao.send({
        Target = msg.From,
        Action = "Transfer",
        Quantity = msg.Tags.Quantity,
        Recipient = msg.Tags.Sender,
        ["X-Action"] = "Refund",
        ["X-Refund-Reason"] = "The sender is already queued for an operation"
      })
    end
  end

  return res
end

return mod
