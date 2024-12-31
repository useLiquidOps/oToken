Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

require(".utils.assignment").init(ao)

local process = { _version = "0.0.1" }

local coroutine = require "coroutine"

local friend = require ".controller.friend"
local config = require ".controller.config"
local queue = require ".controller.queue"

local balance = require ".token.balance"
local token = require ".token.token"
local transfer = require ".token.transfer"

local pool = require ".borrow.pool"
local position = require ".borrow.position"
local repay = require ".borrow.repay"
local borrow = require ".borrow.borrow"
local interest = require ".borrow.interest"

local oracle = require ".liquidations.oracle"
local liquidate = require ".liquidations.liquidate"

local mint = require ".supply.mint"
local price = require ".supply.price"
local reserves = require ".supply.reserves"
local redeem = require ".supply.redeem"

local utils = require ".utils.utils"

HandlersAdded = HandlersAdded or false

-- add handlers for inputs
local function setup_handlers()
  -- only add handlers once
  if HandlersAdded then return end

  -- setup must be in this order (as the first handler)
  Handlers.once(
    "setup",
    function () return "continue" end,
    function (msg, env)
      pool.setup(msg, env)
      token.setup(msg, env)
      oracle.setup(msg, env)
    end
  )

  -- current timestamp sync
  -- (this is required for coroutines, so they always
  -- have the up-to-date timestamp and they don't have
  -- to rely on the resumed handler's timestamp)
  Handlers.add(
    "timestamp-sync",
    Handlers.utils.continue({}),
    pool.syncTimestamp
  )

  -- oracle timeout sync (must be the second handler)
  Handlers.add(
    "oracle-timeout-sync",
    Handlers.utils.continue({}),
    oracle.timeoutSync
  )
  -- interest payment sync (must be the third handler)
  Handlers.add(
    "borrow-loan-interest-sync-dynamic",
    Handlers.utils.continue(
      Handlers.utils.hasMatchingTagOf("Action", {
        "Borrow",
        "Repay",
        "Borrow-Balance",
        "Borrow-Capacity",
        "Position",
        "Global-Position",
        "Positions",
        "Redeem",
        "Transfer",
        "Liquidate-Borrow",
        "Mint"
      })
    ),
    interest.syncInterests
  )

  -- validate incoming transfers, refund 3rd party tokens
  Handlers.add(
    "supply-mint-refund-foreign-token",
    function (msg)
      return msg.Tags.Action == "Credit-Notice" and msg.From ~= CollateralID
    end,
    mint.invalidTokenRefund
  )

  -- communication with the controller
  Handlers.add(
    "controller-friend-add",
    { From = ao.env.Process.Owner, Action = "Add-Friend" },
    friend.add
  )
  Handlers.add(
    "controller-friend-remove",
    { From = ao.env.Process.Owner, Action = "Remove-Friend" },
    friend.remove
  )
  Handlers.add(
    "controller-friend-list",
    Handlers.utils.hasMatchingTag("Action", "List-Friends"),
    friend.list
  )
  Handlers.add(
    "controller-config-oracle",
    { From = ao.env.Process.Owner, Action = "Set-Oracle" },
    config.setOracle
  )
  Handlers.add(
    "controller-config-collateral-factor",
    { From = ao.env.Process.Owner, Action = "Set-Collateral-Factor" },
    config.setCollateralFactor
  )
  Handlers.add(
    "controller-config-liquidation-threshold",
    { From = ao.env.Process.Owner, Action = "Set-Liquidation-Threshold" },
    config.setLiquidationThreshold
  )
  Handlers.add(
    "controller-config-value-limit",
    { From = ao.env.Process.Owner, Action = "Set-Value-Limit" },
    config.setValueLimit
  )

  Handlers.advanced({
    name = "liquidate-borrow",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      Sender = ao.env.Process.Owner,
      ["X-Action"] = "Liquidate-Borrow"
    },
    handle = liquidate.liquidateBorrow,
    errorHandler = liquidate.refund
  })
  Handlers.add(
    "liquidate-position",
    { From = ao.env.Process.Owner, Action = "Liquidate-Position" },
    liquidate.liquidatePosition
  )

  Handlers.add(
    "borrow-loan-interest-get",
    Handlers.utils.hasMatchingTag("Action", "Get-APR"),
    interest.interestRate
  )
  Handlers.add(
    "borrow-loan-interest-sync-static",
    Handlers.utils.hasMatchingTag("Action", "Sync-Interest"),
    interest.syncInterestForUser
  )
  Handlers.add(
    "borrow-loan-borrow",
    Handlers.utils.hasMatchingTag("Action", "Borrow"),
    -- needs unqueueing because of coroutines
    queue.useQueue(borrow)
  )
  Handlers.advanced({
    name = "borrow-repay",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      ["X-Action"] = "Repay"
    },
    handle = repay.handler,
    errorHandler = repay.error
  })
  Handlers.add(
    "borrow-position-balance",
    Handlers.utils.hasMatchingTag("Action", "Borrow-Balance"),
    position.balance
  )
  Handlers.add(
    "borrow-position-capacity",
    Handlers.utils.hasMatchingTag("Action", "Borrow-Capacity"),
    position.capacity
  )
  Handlers.add(
    "borrow-position-collateralization",
    Handlers.utils.hasMatchingTag("Action", "Position"),
    position.position
  )
  Handlers.add(
    "borrow-position-global-collateralization",
    Handlers.utils.hasMatchingTag("Action", "Global-Position"),
    position.globalPosition
  )
  Handlers.add(
    "borrow-position-all-positions",
    Handlers.utils.hasMatchingTag("Action", "Positions"),
    position.allPositions
  )

  Handlers.advanced({
    name = "supply-mint",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      ["X-Action"] = "Mint"
    },
    handle = mint.handler,
    errorHandler = mint.error
  })
  Handlers.add(
    "supply-price",
    Handlers.utils.hasMatchingTag("Action", "Get-Price"),
    price.handler
  )
  Handlers.add(
    "supply-reserves",
    Handlers.utils.hasMatchingTag("Action", "Get-Reserves"),
    reserves
  )
  -- needs unqueueing because of coroutines
  Handlers.add(
    "supply-redeem",
    Handlers.utils.hasMatchingTag("Action", "Redeem"),
    queue.useQueue(redeem)
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
  -- needs unqueueing because of coroutines
  Handlers.add(
    "token-transfer",
    Handlers.utils.hasMatchingTag("Action", "Transfer"),
    queue.useQueue(transfer)
  )

  HandlersAdded = true
end

function process.handle(msg, env)
  -- add reply and forward actions
  ao.add_message_actions(msg)

  -- try to setup env
  local setup_res = ao.init(msg, env)

  if not setup_res then
    if msg.From ~= ao.id then
      msg.reply({
        Target = msg.From,
        Action = (msg.Action and msg.Action or "Unknown") .. "-Error",
        Error = "Message or assignment not trusted"
      })
    end

    return ao.result()
  end

  -- add handlers
  setup_handlers()

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
    -- call default error handler
    Handlers.defaultErrorHandler(msg, env, result)

    return ao.result()
  end

  return ao.result()
end

return process
