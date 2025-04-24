local utils = require ".utils.utils"

local mod = {}

-- Add or remove a user from the queue in the controller
---@param address string User address
---@param queued boolean User queue status
---@return { receive: fun(): boolean; notifyOnFailedQueue: function }
function mod.setQueued(address, queued)
  -- try to update the queue
  local msg = ao.send({
    Target = Controller,
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

-- Make a handle function use the global queue of the controller
---@param handle HandlerFunction Handle function to wrap
---@param errorHandler fun(msg: Message, env: Message, err: unknown)? Optional error handler
---@return HandlerFunction
function mod.useQueue(handle, errorHandler)
  return function (msg, env)
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
      local err = "The sender is already queued for an operation"

      -- call the error handler (if there is one)
      -- with a queue error
      if errorHandler ~= nil then
        errorHandler(msg, env, err)
      else
        -- no error handler, throw the error
        error(err)
      end

      return
    end

    -- call the handler
    local status, err = pcall(handle, msg, env)

    -- unqueue and notify if it failed
    mod
      .setQueued(sender, false)
      .notifyOnFailedQueue()

    if not status then
      if errorHandler ~= nil then
        errorHandler(msg, env, err or "Unknown error")
      else
        -- no error handler, throw the error
        error(err)
      end
    end
  end
end

return mod
