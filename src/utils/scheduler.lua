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
      timeout = {
        type = "milliseconds",
        value = Timestamp + 1
      },
      handle = function (_msg)
        table.insert(responses, _msg)

        -- continue execution only when all responses are back
        if #responses == #messages then
          -- if the result of the resumed coroutine is an error, then we should bubble it up to the process
          local _, success, errmsg = coroutine.resume(thread, responses, false)

          assert(success, errmsg)
        end
      end,
      onRemove = function (reason)
        -- do not continue if the handler wasn't removed because of a timeout
        -- or if the coroutine has already been resumed
        if reason ~= "timeout" or coroutine.status(thread) ~= "suspended" then return end

        -- resume execution on timeout, because a timeout
        -- invalidates all results
        local _, success, errmsg = coroutine.resume(thread, {}, true)

        assert(success, errmsg)
      end
    })
    Handlers.onceNonce = Handlers.onceNonce + 1
  end

  -- yield execution, till all responses are back
  local result, expired = coroutine.yield({
    From = messages[#messages],
    ["X-Reference"] = tostring(ao.reference)
  })

  -- check if expired
  assert(not expired, "Response expired")

  return result
end

return mod
