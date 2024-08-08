Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

require(".utils.assignment").init(ao)

local process = { _version = "0.0.1" }

local coroutine = require "coroutine"

local balance = require ".token.balance"
local token = require ".token.token"
local transfer = require ".token.transfer"

function process.handle(msg, env)
  -- setup env
  local setup_res = ao.init(msg, env)

  if not setup_res then
    ao.send({
      Target = msg.From,
      Action = msg.Action and msg.Action .. "-Error" or nil,
      Data = "Message or assignment not trusted"
    })

    return ao.result()
  end

  -- add reply and forward actions
  ao.add_message_actions(msg)

  -- eval handlers
  local co = coroutine.create(function() return pcall(Handlers.evaluate, msg, ao.env) end)
  local _, status, result = coroutine.resume(co)

  table.insert(Handlers.coroutines, co)
  for i, x in ipairs(Handlers.coroutines) do
    if coroutine.status(x) == "dead" then
      table.remove(Handlers.coroutines, i)
    end
  end

  if not status then
    ao.send({
      Target = msg.From,
      Action = msg.Action and msg.Action .. "-Error" or nil,
      Error = tostring(result)
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
