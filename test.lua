--[[Handlers.add(
  "test",
  { Action = "Test" },
  function ()
    local function schedule(...)
      -- get the running handler's thread
      local thread = coroutine.running()

      -- repsonse handler
      local responses = {}
      local messages = {...}

      ---@type HandlerFunction
      local function responseHandler(msg)
        table.insert(responses, msg)

        -- continue execution when all responses are back
        if #responses == #messages then
          coroutine.resume(thread, messages)
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
      return coroutine.yield()
    end

    Msgs = schedule(
      {
        Target = "LMcKyQuCsAJgUuBEb25BdxwFberI_sOJTiQGspG3oEc",
        Action = "Balance"
      },
      {
        Target = "LMcKyQuCsAJgUuBEb25BdxwFberI_sOJTiQGspG3oEc",
        Action = "Info"
      }
    )
  end
)]]--

Handlers.add(
  "test2",
  { Action = "Test2" },
  function ()
    local coroutine = require "coroutine"

    local function schedule(msg)
      local thread = coroutine.running()
      local res = {}

      ao.send(msg)
      return Handlers.receive(
        { From = msg.Target, ["X-Reference"] = tostring(ao.reference) },
        function (message)
          RES = message
        end
      )
    end

    schedule({
      Target = "LMcKyQuCsAJgUuBEb25BdxwFberI_sOJTiQGspG3oEc",
      Action = "Balance"
    })
    Handlers.receive(
      { From = msg.Target, ["X-Reference"] = tostring(ao.reference) }
    )
  end
)