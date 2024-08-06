Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

local process = { _version = "0.0.1" }

local balance = require ".token.balance"
local token = require ".token.token"
local transfer = require ".token.transfer"

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

  -- setup submodules
  token.init(msg, env)

  if msg.Action == "Info" then token.info(msg)
  elseif msg.Action == "Total-Supply" then token.total_supply(msg)
  elseif msg.Action == "Balance" then balance.balance(msg)
  elseif msg.Action == "Balances" then balance.balances(msg)
  elseif msg.Action == "Transfer" then transfer(msg)
  end

  return ao.result()
end

return process
