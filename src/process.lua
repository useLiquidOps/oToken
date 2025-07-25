Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

require(".utils.assignment").init(ao)

local process = { _version = "0.0.1" }

local coroutine = require "coroutine"

local friend = require ".controller.friend"
local config = require ".controller.config"
local queue = require ".controller.queue"
local cooldown = require ".controller.cooldown"
local updater = require ".controller.updater"
local reserves = require ".controller.reserves"

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
local rate = require ".supply.rate"
local redeem = require ".supply.redeem"
local delegation = require ".supply.delegation"

local utils = require ".utils.utils"
local precision = require ".utils.precision"

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
      token.setup(msg, env)
      pool.setup(msg, env)
      oracle.setup(msg, env)
      cooldown.setup(msg, env)
      delegation.setup(msg, env)
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

  -- accrue interest globally, on all messages
  Handlers.add(
    "borrow-loan-accrue-interest",
    Handlers.utils.continue({}),
    interest.accrueInterest
  )

  -- cooldown list sync
  Handlers.add(
    "controller-cooldown-sync",
    Handlers.utils.continue({}),
    cooldown.sync
  )

  -- validate incoming transfers, refund 3rd party tokens
  Handlers.add(
    "supply-mint-refund-foreign-token",
    function (msg)
      if msg.Tags.Action ~= "Credit-Notice" then
        return false -- not a token transfer
      end
      if WrappedAOToken ~= nil and msg.From == AOToken and msg.Tags.Sender == WrappedAOToken then
        return false -- this oToken process accrues AO and the message is a wAO claim response
      end
      if msg.From ~= CollateralID then
        return true -- unknown token
      end
      if utils.includes(msg.Tags["X-Action"], {
          "Repay",
          "Mint",
          "Liquidate-Borrow"
        }) then
        return false -- used by other actions so keep
      end
      return true -- unknow tag
    end,
    mint.invalidTokenRefund
  )
  -- skip handling debit notices (do not throw unhandled error)
  Handlers.add(
    "no-debit-notice",
    { Action = "Debit-Notice" },
    function () end
  )

  -- apply cooldown limit for user interactions
  Handlers.advanced({
    name = "controller-cooldown-gate",
    pattern = Handlers.utils.continue(
      Handlers.utils.hasMatchingTagOf(
        "Action",
        { "Borrow", "Redeem" }
      )
    ),
    handle = cooldown.gate,
    errorHandler = cooldown.refund
  })

  -- accrued AO distribution for actions that update oToken balances
  Handlers.add(
    "supply-delegate-ao",
    { Action = "Delegate" },
    delegation.delegate
  )

  -- communication with the controller
  Handlers.add(
    "controller-updater",
    { From = Controller, Action = "Update" },
    updater
  )
  Handlers.add(
    "controller-friend-add",
    { From = Controller, Action = "Add-Friend" },
    friend.add
  )
  Handlers.add(
    "controller-friend-remove",
    { From = Controller, Action = "Remove-Friend" },
    friend.remove
  )
  Handlers.add(
    "controller-friend-list",
    Handlers.utils.hasMatchingTag("Action", "List-Friends"),
    friend.list
  )
  Handlers.add(
    "controller-reserves-total",
    Handlers.utils.hasMatchingTag("Action", "Total-Reserves"),
    function (msg)
      msg.reply({
        ["Total-Reserves"] = precision.formatInternalAsNative(Reserves, "roundup")
      })
    end
  )

  -- Reserved for future use in a governance model
  Handlers.add(
    "controller-config-update",
    { From = Controller, Action = "Update-Config" },
    config.update
  )
  Handlers.add(
    "controller-toggle-interactions",
    { From = Controller, Action = "Toggle-Interactions" },
    config.toggleInteractions
  )

  Handlers.advanced({
    name = "liquidate-borrow",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      Sender = Controller,
      ["X-Action"] = "Liquidate-Borrow"
    },
    handle = liquidate.liquidateBorrow,
    errorHandler = liquidate.refund
  })
  Handlers.add(
    "liquidate-position",
    Handlers.utils.hasMatchingTag("Action", "Liquidate-Position"),
    liquidate.liquidatePosition
  )

  -- Reserved for future use in a governance model
  Handlers.add(
    "controller-reserves-withdraw",
    { From = Controller, Action = "Withdraw-From-Reserves" },
    reserves.withdraw
  )

  -- Reserved for future use in a governance model
  Handlers.add(
    "controller-reserves-deploy",
    { From = Controller, Action = "Deploy-From-Reserves" },
    reserves.deploy
  )

  Handlers.add(
    "controller-cooldown-list",
    Handlers.utils.hasMatchingTag("Action", "Cooldowns"),
    cooldown.list
  )
  Handlers.add(
    "controller-cooldown-is-on-cooldown",
    Handlers.utils.hasMatchingTag("Action", "Is-Cooldown"),
    cooldown.isOnCooldown
  )

  Handlers.add(
    "borrow-loan-interest-get",
    Handlers.utils.hasMatchingTag("Action", "Get-APR"),
    interest.interestRate
  )
  Handlers.add(
    "borrow-load-interest-supply-rate-get",
    Handlers.utils.hasMatchingTag("Action", "Get-Supply-APY"),
    interest.supplyRate
  )
  Handlers.add(
    "borrow-loan-interest-sync-static",
    Handlers.utils.hasMatchingTag("Action", "Sync-Interest"),
    function (msg)
      local target = msg.Tags.Recipient or msg.From
      local borrowBalance = precision.toNativePrecision(
        interest.accrueInterestForUser(target),
        "roundup"
      )

      msg.reply({ ["Borrow-Balance"] = tostring(borrowBalance) })
    end
  )
  Handlers.advanced(queue.useQueue({
    name = "borrow-loan-borrow",
    pattern = { Action = "Borrow" },
    handle = oracle.withOracle(borrow)
  }))
  Handlers.advanced(queue.useQueue({
    name = "borrow-repay",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      ["X-Action"] = "Repay"
    },
    handle = repay.handler,
    errorHandler = repay.error
  }))
  Handlers.add(
    "borrow-position-collateralization",
    Handlers.utils.hasMatchingTag("Action", "Position"),
    position.handlers.localPosition
  )
  Handlers.add(
    "borrow-position-global-collateralization",
    Handlers.utils.hasMatchingTag("Action", "Global-Position"),
    oracle.withOracle(position.handlers.globalPosition)
  )
  Handlers.add(
    "borrow-position-all-positions",
    Handlers.utils.hasMatchingTag("Action", "Positions"),
    position.handlers.allPositions
  )

  Handlers.advanced(queue.useQueue({
    name = "supply-mint",
    pattern = {
      From = CollateralID,
      Action = "Credit-Notice",
      ["X-Action"] = "Mint"
    },
    handle = mint.handler,
    errorHandler = mint.error
  }))
  Handlers.add(
    "supply-price",
    Handlers.utils.hasMatchingTag("Action", "Exchange-Rate-Current"),
    rate.exchangeRate
  )
  Handlers.add(
    "supply-cash",
    Handlers.utils.hasMatchingTag("Action", "Cash"),
    function (msg)
      msg.reply({ Cash = precision.formatInternalAsNative(Cash, "roundup") })
    end
  )
  Handlers.add(
    "supply-total-borrows",
    Handlers.utils.hasMatchingTag("Action", "Total-Borrows"),
    function (msg)
      msg.reply({
        ["Total-Borrows"] = precision.formatInternalAsNative(TotalBorrows, "roundup")
      })
    end
  )
  Handlers.advanced(queue.useQueue({
    name = "supply-redeem",
    pattern = { Action = "Redeem" },
    handle = oracle.withOracle(redeem)
  }))

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
  Handlers.advanced(queue.useQueue({
    name = "token-transfer",
    pattern = { Action = "Transfer" },
    handle = oracle.withOracle(transfer)
  }))

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
        Action = (msg.Action or "Unknown") .. "-Error",
        Error = "Message or assignment not trusted"
      })
    end

    return ao.result()
  end

  -- the controller is the process spawner
  Controller = Controller or ao.env.Process.Owner

  -- add handlers
  setup_handlers()

  -- eval handlers
  local co = coroutine.create(function() return pcall(Handlers.evaluate, msg, ao.env) end)
  local _, status, result = coroutine.resume(co)

  table.insert(Handlers.coroutines, co)
  Handlers.coroutines = utils.filter(
    function (x)
      return coroutine.status(x) ~= "dead"
    end,
    Handlers.coroutines
  )

  if not status then
    -- call default error handler
    Handlers.defaultErrorHandler(msg, env, result)

    return ao.result()
  end

  return ao.result()
end

return process
