local utils = require ".utils"

local mod = {}

local function findIndexByProp(array, prop, value)
  for index, object in ipairs(array) do
    if object[prop] == value then
      return index
    end
  end
  return nil
end

-- Add a hanlder with a timeout (maxRuns = 1 by default)
---@param name string Handler name
---@param pattern Pattern Handler param
---@param timeout { type: "block" | "timestamp", value: number, onTimeout?: HandlerFunction } Handler timeout config
---@param handle HandlerFunction Function to be called for the handler
function mod.handler(name, pattern, timeout, handle)
  if timeout.type == "block" then timeout.value = timeout.value + Block
  elseif timeout.type == "timestamp" then timeout.value = timeout.value + Timestamp end

  local timeoutHandlerName = "timeout-" .. name

  Handlers.prepend(
    timeoutHandlerName,
    ---@type PatternFunction
    function (msg)
      if timeout.type == "block" and msg["Block-Height"] > timeout.value then
        return "continue"
      elseif timeout.type == "timestamp" and msg.Timestamp > timeout.value then
        return "continue"
      end
      return "skip"
    end,
    function (msg, env)
      -- find handler index
      local idx = findIndexByProp(Handlers.list, "name", name)
      if not idx then return end

      -- remove handler
      table.remove(Handlers.list, idx)

      -- call timeout handler
      if type(timeout.onTimeout) == "function" then
        timeout.onTimeout(msg, env)
      end
    end,
    1
  )

  return Handlers.add(
    name,
    pattern,
    function (msg, env)
      -- remove timeout handler
      Handlers.remove(timeoutHandlerName)

      -- call default handler
      handle(msg, env)
    end,
    1
  )
end

-- Wrap a message to receive it with a timeout
---@param msg OutgoingMessage Message returned from ao.send()
---@param from string? Receive response from another process
function mod.receive(msg, from)
  -- find the reference
  local referenceTag = utils.find(
    ---@param val Tag
    function (val) return val.name == "Reference" end,
    msg.Tags
  )

  assert(referenceTag ~= nil, "No reference set for message")

  -- fill from if not present (by default it is the target)
  if from == nil then from = msg.Target end

  -- add handler and stop execution
  local self = coroutine.running()
  local handlerName = "_once_" .. tostring(Handlers.onceNonce)
  local pattern = {
    From = from,
    ["X-Reference"] = referenceTag.value
  }

  mod.handler(
    handlerName,
    pattern,
    { type = "timestamp", value = 30000 }, -- default timeout is 30s
    function (message)
      local _, success, errmsg = coroutine.resume(self, message)
      assert(success, errmsg)
    end
  )
  Handlers.onceNonce = Handlers.onceNonce + 1

  return coroutine.yield(pattern)
end

return mod
