Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

require(".utils.assignment").init(ao)

local process = { _version = "0.0.1" }

local coroutine = require "coroutine"

local balance = require ".token.balance"
local token = require ".token.token"
local transfer = require ".token.transfer"

local pool = require ".borrow.pool"

local mint = require ".supply.mint"
local price = require ".supply.price"
local reserves = require ".supply.reserves"
local redeem = require ".supply.redeem"

Handlers.add(
  "supply-mint",
  { From = Token, Action = "Credit-Notice", ["X-Action"] = "Mint" },
  mint.handler,
  nil,
  mint.error
)
Handlers.add(
  "supply-price",
  Handlers.utils.hasMatchingTag("Action", "Get-Price"),
  price
)
Handlers.add(
  "supply-reserves",
  Handlers.utils.hasMatchingTag("Action", "Get-Reserves"),
  reserves
)
Handlers.add(
  "suppy-redeem",
  Handlers.utils.hasMatchingTag("Action", "Redeem"),
  redeem.handler,
  nil,
  redeem.error
)

Handlers.add(
  "token-info",
  Handlers.utils.hasMatchingTag("Action", "Info"),
  token.info
)
Handlers.add(
  "token-total-supply",
  Handlers.utils.hasMatchingTag("Action", "Total-Supply"),
  token.total_supply
)
Handlers.add(
  "token-balance",
  Handlers.utils.hasMatchingTag("Action", "Balance"),
  balance.balance
)
Handlers.add(
  "token-all-balances",
  Handlers.utils.hasMatchingTag("Action", "Balances"),
  balance.balances
)
Handlers.add(
  "token-transfer",
  Handlers.utils.hasMatchingTag("Action", "Transfer"),
  transfer
)

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

  -- setup submodules
  pool.init()
  token.init()

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
    msg.reply({
      Action = msg.Action and msg.Action .. "-Error" or nil,
      Error = tostring(result)
    })

    return ao.result()
  end

  return ao.result()
end

return process
