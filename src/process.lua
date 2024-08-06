Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

local process = { _version = "0.0.1" }

function process.handle(msg, env)
  -- setup env
  local setup_res = ao.init(msg, env)

  if not setup_res then
    ao.send({
      Target = msg.From,
      Data = "Message or assignment not trusted"
    })

    return ao.result()
  end

  return ao.result()
end

return process
