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

-- Get the user to be queued, depending on the type of the message
---@param msg Message Message to process
---@return string
function mod.getUserToQueue(msg)
  -- return sender if it is a credit notice
  if msg.Tags.Action == "Credit-Notice" then
    return msg.Tags.Sender
  end

  -- the msg sender should be queued if it is not a credit-notice
  return msg.From
end

-- Make a handler use the global queue of the controller. This is
-- usually needed for handlers that impelement complex behavior by
-- waiting for several message responses before completion to prevent
-- double spending
---@param config table Configuration for the handler
---@return table
function mod.useQueue(config)
  -- original handle function and error handler
  local handle = config.handle
  local errorHandler = config.errorHandler

  -- override handle function to queue and unqueue
  config.handle = function (msg, env)
    local sender = mod.getUserToQueue(msg)

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
        -- do not error() here - that would trigger
        -- the handler's error handler, which would
        -- try to unqueue the user
        Handlers.defaultErrorHandler(msg, env, err)
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

  -- override error handler to unqueue the user
  config.errorHandler = function (msg, env, err)
    -- call wrapped error handler if provided
    if errorHandler ~= nil then
      errorHandler(msg, env, err or "Unknown error")
    else
      Handlers.defaultErrorHandler(msg, env, err)
    end

    -- get user to unqueue
    local sender = mod.getUserToQueue(msg)

    -- unqueue and notify if it failed
    mod
      .setQueued(sender, false)
      .notifyOnFailedQueue()
  end

  return config
end

return mod
