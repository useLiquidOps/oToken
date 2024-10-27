Handlers = require ".utils.handlers"
Utils = require ".utils.utils"
ao = require ".utils.ao"

require(".utils.assignment").init(ao)

local process = { _version = "0.0.1" }

local coroutine = require "coroutine"

local friend = require ".temp_admin.friend"
local config = require ".temp_admin.config"

local balance = require ".token.balance"
local token = require ".token.token"
local transfer = require ".token.transfer"

local pool = require ".borrow.pool"
local position = require ".borrow.position"
local repay = require ".borrow.repay"
local borrow = require ".borrow.borrow"
local interest = require ".borrow.interest"

local oracle = require ".liquidations.oracle"

local mint = require ".supply.mint"
local price = require ".supply.price"
local reserves = require ".supply.reserves"
local redeem = require ".supply.redeem"

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

  -- oracle timeout sync (must be the second handler)
  Handlers.add(
    "oracle-timeout-sync",
    Handlers.utils.continue({}),
    oracle.timeoutSync
  )
  -- interest payment sync (must be the third handler)
  Handlers.add(
    "borrow-loan-interest-sync-dynamic",
    Handlers.utils.continue(Handlers.utils.hasMatchingTagOf("Action", {
      "Borrow", "Repay", "Borrow-Balance", "Borrow-Capacity", "Position", "Global-Position", "Positions", "Redeem", "Transfer"
    })),
    interest.syncInterests
  )

  -- temporary handlers for testnet
  -- these are "admin" functions that will be removed
  -- once the protocol is ready
  Handlers.add(
    "temp-admin-friend-add",
    { From = ao.env.Process.Owner, Action = "Add-Friend" },
    friend.add
  )
  Handlers.add(
    "temp-admin-friend-remove",
    { From = ao.env.Process.Owner, Action = "Remove-Friend" },
    friend.remove
  )
  Handlers.add(
    "temp-admin-friend-list",
    { From = ao.env.Process.Owner, Action = "List-Friends" },
    friend.list
  )
  Handlers.add(
    "temp-admin-config-oracle",
    { From = ao.env.Process.Owner, Action = "Set-Oracle" },
    config.setOracle
  )
  Handlers.add(
    "temp-admin-config-collateral-ratio",
    { From = ao.env.Process.Owner, Action = "Set-Collateral-Ratio" },
    config.setCollateralRatio
  )
  Handlers.add(
    "temp-admin-config-liquidation-threshold",
    { From = ao.env.Process.Owner, Action = "Set-Liquidation-Threshold" },
    config.setLiquidationThreshold
  )
  --

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
    borrow
  )
  Handlers.add(
    "borrow-repay",
    { From = CollateralID, Action = "Credit-Notice", ["X-Action"] = "Repay" },
    repay.handler,
    nil,
    repay.error
  )
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

  Handlers.add(
    "supply-mint",
    { From = CollateralID, Action = "Credit-Notice", ["X-Action"] = "Mint" },
    mint.handler,
    nil,
    mint.error
  )
  Handlers.add(
    "supply-mint-refund-foreign-token",
    function (msg)
      return msg.Tags.Action == "Credit-Notice" and msg.From ~= CollateralID
    end,
    mint.invalidTokenRefund
  )
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
