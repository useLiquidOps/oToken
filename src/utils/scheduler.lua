local coroutine = require "coroutine"

local mod = {}

-- Schedule a batch of messages and wait for all of them
-- to return. Uses lua coroutines under the hood
---@param ... MessageParam
---@return Message[]
function mod.schedule(...)
  -- get the running handler's thread
  local thread = coroutine.running()

  -- repsonse handler
  local responses = {}
  local messages = {...}

  -- if there are no messages to be sent, we don't do anything
  if #messages == 0 then return {} end

  ---@type HandlerFunction
  local function responseHandler(msg)
    table.insert(responses, msg)

    -- continue execution when all responses are back
    if #responses == #messages then
      coroutine.resume(thread, responses)
    end
  end

  -- send messages
  for _, msg in ipairs(messages) do
    ao.send(msg)

    -- wait for response
    Handlers.once(
      { From = msg.Target, ["X-Reference"] = tostring(ao.reference) },
      responseHandler
    )
  end

  -- yield execution, till all responses are back
  return coroutine.yield({ From = messages[#messages], ["X-Reference"] = tostring(ao.reference) })
end

return mod
