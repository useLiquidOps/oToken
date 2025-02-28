local coroutine = require "coroutine"

local mod = {}

---@param ... OutgoingMessage
---@return Message[]
function mod.receiveAll(...)
  local messages = {...}
  local results = {}

  if #messages == 0 then return {} end

  -- get current thread
  ---@type thread|nil
  local thread = coroutine.running()

  -- original handler environment
  local currentErrorHandler = Handlers.currentErrorHandler
  local originalMsg = ao.clone(ao.msg)
  local originalEnv = ao.clone(ao.env)

  -- handles incoming result
  local function handle(result, idx)
    -- insert to the same position as the message
    results[idx] = result

    -- continue exection if all results are in,
    -- throw error if execution errors
    if #results == #messages and thread ~= nil then

      -- TODO: new way of keeping the environment/upvalues
      -- - use string.dump(, true) (true for strip to save space) for coroutine.resume(thread, results)
      -- - run the binary using load()
      -- - include the old "_G" in load() to recreate the exact environment

      local _, success, error = coroutine.resume(thread, results)

      assert(success, error)
    end
  end

  -- handle removal (expiry)
  local function remove(reason)
    -- do not continue if the handler wasn't removed because of a timeout
    -- or if the coroutine has already been resumed
    if reason ~= "timeout" or thread == nil or coroutine.status(thread) ~= "suspended" then return end

    -- protected call the error handler, so if it errors,
    -- it still doesn't affect the main execution
    local success, err = pcall(
      currentErrorHandler,
      originalMsg,
      originalEnv,
      "Response expired"
    )

    -- call default error handler, if the current error
    -- handler also errored
    if not success then
      Handlers.defaultErrorHandler(
        originalMsg,
        originalEnv,
        "Response expired, but expiry was not handled: " .. err
      )
    end

    thread = nil
  end

  -- handle all responses
  for i, msg in ipairs(messages) do
    local normalized = ao.normalize(msg)

    Handlers.advanced({
      name = "_once_" .. tostring(Handlers.onceNonce),
      position = "prepend",
      pattern = {
        From = normalized.Target,
        ["X-Reference"] = normalized.Reference
      },
      maxRuns = 1,
      timeout = Block + 1,
      handle = function (result) handle(result, i) end,
      onRemove = remove
    })
    Handlers.onceNonce = Handlers.onceNonce + 1
  end

  return coroutine.yield({})
end

-- Schedule a batch of messages and wait for all of them
-- to return. Uses lua coroutines under the hood
---@param ... MessageParam
---@return Message[]
function mod.schedule(...)
  -- get the running handler's thread
  local thread = coroutine.running()

  -- original handler environment
  local currentErrorHandler = Handlers.currentErrorHandler
  local originalMsg = ao.msg
  local originalEnv = ao.env

  -- repsonse handler
  local responses = {}
  local messages = {...}

  -- if there are no messages to be sent, we don't do anything
  if #messages == 0 then return {} end

  local function expire()
    -- protected call the error handler, so if it errors,
    -- it still doesn't affect the main execution
    local success, err = pcall(
      currentErrorHandler,
      originalMsg,
      originalEnv,
      "Response expired"
    )

    -- call default error handler, if the current error
    -- handler also errored
    if not success then
      Handlers.defaultErrorHandler(
        originalMsg,
        originalEnv,
        "Response expired, but expiry was not handled: " .. err
      )
    end

    thread = nil
  end

  -- send messages
  for _, msg in ipairs(messages) do
    ao.send(msg)

    -- wait for response
    Handlers.advanced({
      name = "_once_" .. tostring(Handlers.onceNonce),
      position = "prepend",
      pattern = {
        From = msg.Target,
        ["X-Reference"] = tostring(ao.reference)
      },
      maxRuns = 1,
      -- TODO: is this an optimal timeout?
      timeout = Block + 1,
      handle = function (_msg)
        table.insert(responses, _msg)

        -- continue execution only when all responses are back
        if #responses == #messages then
          -- this should not happen
          if not thread then
            currentErrorHandler(originalMsg, originalEnv, "The response(s) expired previously")
            return
          end

          local newMsg, newEnv = ao.msg, ao.env
          ao.msg, ao.env = originalMsg, originalEnv

          -- if the result of the resumed coroutine is an error, then we should bubble it up to the process
          local _, success, errmsg = coroutine.resume(thread, responses)

          ao.msg, ao.env = newMsg, newEnv

          if not success then
            currentErrorHandler(originalMsg, originalEnv, errmsg)
          end
        end
      end,
      onRemove = function (reason)
        -- do not continue if the handler wasn't removed because of a timeout
        -- or if the coroutine has already been resumed
        if reason ~= "timeout" or thread == nil or coroutine.status(thread) ~= "suspended" then return end

        expire()
      end
    })
    Handlers.onceNonce = Handlers.onceNonce + 1
  end

  -- yield execution, till all responses are back
  local result = coroutine.yield({
    From = messages[#messages],
    ["X-Reference"] = tostring(ao.reference)
  })

  return result
end

return mod
