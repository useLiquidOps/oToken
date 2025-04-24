local coroutine = require "coroutine"
local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"

local liquidations = {}
local assertions = {}
local scheduler = {}
local oracle = {}
local tokens = {}

-- oToken module ID
Module = Module or "C6CQfrL29jZ-LYXV2lKn09d3pBIM6adDFwWqh2ICikM"

-- oracle id and tolerance
Oracle = Oracle or "4fVi8P-xSRWxZ0EE0EpltDe8WJJvcD9QyFXMqfk-1UQ"
MaxOracleDelay = MaxOracleDelay or 1200000

-- admin addresses
Owners = Owners or {}

-- liquidops logo tx id
ProtocolLogo = ProtocolLogo or ""

-- holds all the processes that are part of the protocol
-- a member consists of the following fields:
-- - id: string (this is the address of the collateral supported by LiquidOps)
-- - ticker: string (the ticker of the collateral)
-- - oToken: string (the address of the oToken process for the collateral)
-- - denomination: integer (the denomination of the collateral)
---@type Friend[]
Tokens = Tokens or {}

-- queue for operations in oTokens that involve
-- the collateral/collateralization
---@type string[]
CollateralQueue = CollateralQueue or {}

-- queue for liquidations
LiquidationQueue = LiquidationQueue or {}

-- current timestamp
Timestamp = Timestamp or 0

-- cached auctions (position wallet address, timestamp when discovered)
---@type table<string, number>
Auctions = Auctions or {}

-- maximum and minimum discount that can be applied to a loan in percentages
MaxDiscount = MaxDiscount or 5
MinDiscount = MinDiscount or 1

-- the period till the auction reaches the minimum discount (market price)
DiscountInterval = DiscountInterval or 1000 * 60 * 60 -- 1 hour

PrecisionFactor = 1000000

---@alias TokenData { ticker: string, denomination: number }
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias CollateralBorrow { token: string, ticker: string, quantity: string }
---@alias QualifyingPosition { target: string, depts: CollateralBorrow[], collaterals: CollateralBorrow[], discount: string }

Handlers.add(
  "sync-timestamp",
  function () return "continue" end,
  function (msg) Timestamp = msg.Timestamp end
)

Handlers.add(
  "info",
  { Action = "Info" },
  function (msg)
    msg.reply({
      Name = "LiquidOps Controller",
      Module = Module,
      Oracle = Oracle,
      ["Max-Discount"] = tostring(MaxDiscount),
      ["Min-Discount"] = tostring(MinDiscount),
      ["Discount-Interval"] = tostring(DiscountInterval),
      Data = json.encode(Tokens)
    })
  end
)

Handlers.add(
  "sync-auctions",
  Handlers.utils.hasMatchingTagOf("Action", { "Cron", "Get-Liquidations" }),
  function (msg)
    -- fetch prices first, so the processing of the positions won't be delayed
    local rawPrices = oracle.sync()

    -- generate position messages
    ---@type MessageParam[]
    local positionMsgs = {}

    for _, token in ipairs(Tokens) do
      table.insert(positionMsgs, { Target = token.oToken, Action = "Positions" })
    end

    -- get all user positions
    ---@type Message[]
    local rawPositions = scheduler.schedule(table.unpack(positionMsgs))

    -- protocol positions in USD
    ---@type table<string, { liquidationLimit: Bint, borrowBalance: Bint, debts: CollateralBorrow[], collaterals: CollateralBorrow[] }>
    local allPositions = {}
    local zero = bint.zero()

    -- add positions
    for _, market in ipairs(rawPositions) do
      ---@type boolean, table<string, { Capacity: string, ["Borrow-Balance"]: string, Collateralization: string, ["Liquidation-Limit"]: string }>
      local parsed, marketPositions = pcall(json.decode, market.Data)
      assert(parsed, "Could not parse market data for " .. market.From)

      local ticker = market.Tags["Collateral-Ticker"]
      local denomination = tonumber(market.Tags["Collateral-Denomination"]) or 0
      local collateral = utils.find(
        function (t) return t.oToken == market.From end,
        Tokens
      )

      -- add each position in the market by their usd value
      for address, position in pairs(marketPositions) do
        local posLiquidationLimit = bint(position["Liquidation-Limit"] or 0)
        local posBorrowBalance = bint(position["Borrow-Balance"] or 0)

        local hasCollateral = bint.ult(zero, posLiquidationLimit)
        local hasLoan = bint.ult(zero, posBorrowBalance)

        if hasCollateral or hasLoan then
          allPositions[address] = allPositions[address] or {
            liquidationLimit = zero,
            borrowBalance = zero,
            debts = {},
            collaterals = {}
          }

          -- add liquidation limit
          if hasCollateral and collateral ~= nil then
            allPositions[address].liquidationLimit = allPositions[address].liquidationLimit + oracle.getValue(
              rawPrices,
              posLiquidationLimit,
              ticker,
              denomination
            )
            table.insert(allPositions[address].collaterals, {
              token = collateral.id,
              ticker = ticker,
              quantity = position.Collateralization
            })
          end

          -- add borrow balance
          if hasLoan and collateral ~= nil  then
            allPositions[address].borrowBalance = allPositions[address].borrowBalance + oracle.getValue(
              rawPrices,
              posBorrowBalance,
              ticker,
              denomination
            )
            table.insert(allPositions[address].debts, {
              token = collateral.id,
              ticker = ticker,
              quantity = position["Borrow-Balance"]
            })
          end
        end
      end
    end

    ---@type QualifyingPosition[]
    local qualifyingPositions = {}

    -- now find the positions that can be auctioned
    -- and update existing auctions
    for address, position in pairs(allPositions) do
      -- check if the position can be liquidated
      if bint.ult(position.liquidationLimit, position.borrowBalance) then
        -- add auction
        liquidations.addAuction(address, msg.Timestamp)

        -- calculate discount
        local discount = tokens.getDiscount(address)

        if msg.Tags.Action == "Get-Liquidations" then
          table.insert(qualifyingPositions, {
            target = address,
            debts = position.debts,
            collaterals = position.collaterals,
            discount = discount
          })
        end
      else
        -- remove auction, it is no longer necessary
        liquidations.removeAuction(address)
      end
    end

    if msg.Tags.Action == "Get-Liquidations" then
      msg.reply({
        Data = json.encode({
          liquidations = qualifyingPositions,
          tokens = Tokens,
          maxDiscount = MaxDiscount,
          minDiscount = MinDiscount,
          discountInterval = DiscountInterval,
          prices = rawPrices,
          precisionFactor = PrecisionFactor
        })
      })
    end
  end
)

-- Verify if the caller of an admin function is
-- authorized to run this action
---@param action string Accepted action
---@return PatternFunction
function assertions.isAdminAction(action)
  return function (msg)
    if msg.From ~= ao.env.Process.Id and not utils.includes(msg.From, Owners) then
      return false
    end

    return msg.Tags.Action == action
  end
end

Handlers.add(
  "list",
  assertions.isAdminAction("List"),
  function (msg)
    -- token to be listed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )
    assert(
      utils.find(function (t) return t.id == token end, Tokens) == nil,
      "Token already listed"
    )

    -- check configuration
    local liquidationThreshold = tonumber(msg.Tags["Liquidation-Threshold"])
    local collateralFactor = tonumber(msg.Tags["Collateral-Factor"])
    local reserveFactor = tonumber(msg.Tags["Reserve-Factor"])
    local baseRate = tonumber(msg.Tags["Base-Rate"])
    local initRate = tonumber(msg.Tags["Init-Rate"])
    local cooldownPeriod = tonumber(msg.Tags["Cooldown-Period"])

    assert(
      collateralFactor ~= nil and type(collateralFactor) == "number",
      "Invalid collateral factor"
    )
    assert(
      collateralFactor // 1 == collateralFactor and collateralFactor >= 0 and collateralFactor <= 100,
      "Collateral factor has to be a whole percentage between 0 and 100"
    )
    assert(
      liquidationThreshold ~= nil and type(liquidationThreshold) == "number",
      "Invalid liquidation threshold"
    )
    assert(
      liquidationThreshold // 1 == liquidationThreshold and liquidationThreshold >= 0 and liquidationThreshold <= 100,
      "Liquidation threshold has to be a whole percentage between 0 and 100"
    )
    assert(
      liquidationThreshold > collateralFactor,
      "Liquidation threshold must be greater than the collateral factor"
    )
    assert(
      reserveFactor ~= nil and type(reserveFactor) == "number",
      "Invalid reserve factor"
    )
    assert(
      reserveFactor // 1 == reserveFactor and reserveFactor >= 0 and reserveFactor <= 100,
      "Reserve factor has to be a whole percentage between 0 and 100"
    )
    assert(
      baseRate ~= nil and assertions.isValidNumber(baseRate),
      "Invalid base rate"
    )
    assert(
      initRate ~= nil and assertions.isValidNumber(initRate),
      "Invalid init rate"
    )
    assert(
      assertions.isTokenQuantity(msg.Tags["Value-Limit"]),
      "Invalid value limit"
    )
    assert(
      cooldownPeriod ~= nil and assertions.isValidNumber(cooldownPeriod),
      "Invalid cooldown period"
    )

    -- check if token is supported
    local supported, info = tokens.isSupported(token)

    assert(supported, "Token not supported by the protocol")

    -- spawn logo
    local logo = msg.Tags.Logo or info.Tags.Logo

    -- the oToken configuration
    local config = {
      Name = "LiquidOps " .. tostring(info.Tags.Name or info.Tags.Ticker or ""),
      ["Collateral-Id"] = token,
      ["Collateral-Ticker"] = info.Tags.Ticker,
      ["Collateral-Name"] = info.Tags.Name,
      ["Collateral-Denomination"] = info.Tags.Denomination,
      ["Collateral-Factor"] = msg.Tags["Collateral-Factor"],
      ["Liquidation-Threshold"] = tostring(liquidationThreshold),
      ["Reserve-Factor"] = tostring(reserveFactor),
      ["Base-Rate"] = msg.Tags["Base-Rate"],
      ["Init-Rate"] = msg.Tags["Init-Rate"],
      ["Value-Limit"] = msg.Tags["Value-Limit"],
      ["Cooldown-Period"] = msg.Tags["Cooldown-Period"],
      Oracle = Oracle,
      ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
      Logo = logo,
      Authority = ao.authorities[1],
      Friends = json.encode(Tokens)
    }

    -- spawn new oToken process
    local spawnResult = ao.spawn(Module, config).receive()
    local spawnedID = spawnResult.Tags.Process

    -- notify all other tokens
    for _, t in ipairs(Tokens) do
      if t.oToken ~= spawnedID then
        ao.send({
          Target = t.oToken,
          Action = "Add-Friend",
          Friend = spawnedID,
          Token = token,
          Ticker = info.Tags.Ticker,
          Denomination = info.Tags.Denomination
        })
      end
    end

    -- add token to tokens list
    table.insert(Tokens, {
      id = token,
      ticker = info.Tags.Ticker,
      oToken = spawnedID,
      denomination = tonumber(info.Tags.Denomination) or 0
    })

    msg.reply({
      Action = "Token-Listed",
      Token = token,
      ["Spawned-Id"] = spawnedID,
      Data = json.encode(config)
    })
  end
)

Handlers.add(
  "unlist",
  assertions.isAdminAction("Unlist"),
  function (msg)
    -- token to be removed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )

    -- find token index
    ---@type integer|nil
    local idx = utils.find(
      function (t) return t.id == token end,
      Tokens
    )

    assert(type(idx) == "number", "Token is not listed")

    -- id of the oToken for this token
    local oToken = Tokens[idx].oToken

    -- unlist
    table.remove(Tokens, idx)

    -- notify all other oTokens
    for _, t in ipairs(Tokens) do
      ao.send({
        Target = t.oToken,
        Action = "Remove-Friend",
        Friend = oToken
      })
    end

    msg.reply({
      Action = "Token-Unlisted",
      Token = token,
      ["Removed-Id"] = oToken
    })
  end
)

Handlers.add(
  "batch-update",
  assertions.isAdminAction("Batch-Update"),
  function (msg)
    -- check if update is already in progress
    assert(not UpdateInProgress, "An update is already in progress")

    -- generate update msgs
    ---@type MessageParam[]
    local updateMsgs = {}

    for _, t in ipairs(Tokens) do
      table.insert(updateMsgs, {
        Target = t.oToken,
        Action = "Update",
        Data = msg.Data
      })
    end

    -- set updating in progress. this will halt interactions
    -- by making the queue check always return true for any
    -- address
    UpdateInProgress = true

    -- request updates
    ---@type Message[]
    local updates = scheduler.schedule(table.unpack(updateMsgs))

    UpdateInProgress = false

    -- filter failed updates
    local failed = utils.filter(
      ---@param res Message
      function (res) return res.Tags.Error ~= nil or res.Tags.Updated ~= "true" end,
      updates
    )

    -- reply with results
    msg.reply({
      Updated = tostring(#Tokens - #failed),
      Failed = tostring(#failed),
      Data = json.encode(utils.map(
        ---@param res Message
        function (res) return res.From end,
        failed
      ))
    })
  end
)

Handlers.add(
  "get-tokens",
  { Action = "Get-Tokens" },
  function (msg)
    msg.reply({
      Data = json.encode(Tokens)
    })
  end
)

Handlers.add(
  "get-oracle",
  { Action = "Get-Oracle" },
  function (msg)
    msg.reply({ Oracle = Oracle })
  end
)

Handlers.add(
  "refund-invalid",
  function (msg)
    return msg.Tags.Action == "Credit-Notice" and
      msg.Tags["X-Action"] ~= "Liquidate"
  end,
  function (msg)
    ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = msg.Tags.Sender,
      ["X-Action"] = "Refund",
      ["X-Refund-Reason"] = "This process does not accept the transferred token " .. msg.From
    })
  end
)

Handlers.add(
  "liquidate",
  { Action = "Credit-Notice", ["X-Action"] = "Liquidate" },
  function (msg)
    -- liquidation target
    local target = msg.Tags["X-Target"]

    -- liquidator address
    local liquidator = msg.Tags.Sender

    -- token to be liquidated, currently lent to the target
    -- (the token that is paying for the loan = transferred token)
    local liquidatedToken = msg.From

    -- the token that the liquidator will earn for
    -- paying off the loan
    -- the user has to have a position in this token
    local rewardToken = msg.Tags["X-Reward-Token"]

    -- prepare liquidation, check required environment
    local success, errorMsg, expectedRewardQty, oTokensParticipating, removeWhenDone = pcall(function ()
      assert(
        assertions.isAddress(target) and target ~= liquidator,
        "Invalid liquidation target"
      )
      assert(
        assertions.isAddress(liquidator),
        "Invalid liquidator address"
      )
      assert(
        liquidatedToken ~= rewardToken,
        "Can't liquidate for the same token"
      )
      assert(
        assertions.isAddress(rewardToken),
        "Invalid reward token address"
      )
      assert(
        assertions.isTokenQuantity(msg.Tags.Quantity),
        "Invalid transfer quantity"
      )
      assert(
        assertions.isTokenQuantity(msg.Tags["X-Min-Expected-Quantity"]),
        "Invalid minimum expected quantity"
      )

      -- try to find the liquidated token, the reward token and
      -- generate the position messages in one loop for efficiency
      ---@type { liquidated: string; reward: string; }
      local oTokensParticipating = {}

      ---@type MessageParam[]
      local positionMsgs = {}

      for _, t in ipairs(Tokens) do
        if t.id == liquidatedToken then oTokensParticipating.liquidated = t.oToken
        elseif t.id == rewardToken then oTokensParticipating.reward = t.oToken end

        table.insert(positionMsgs, {
          Target = t.oToken,
          Action = "Position",
          Recipient = target
        })
      end

      assert(
        oTokensParticipating.liquidated ~= nil,
        "Cannot liquidate the incoming token as it is not listed"
      )
      assert(
        oTokensParticipating.reward ~= nil,
        "Cannot liquidate for the reward token as it is not listed"
      )

      -- fetch prices first so the user positions won't be outdated
      local prices = oracle.sync()

      -- check user position
      ---@type Message[]
      local positions = scheduler.schedule(table.unpack(positionMsgs))

      -- get tokens that need a price fetch
      local zero = bint.zero()

      ---@type PriceParam[], PriceParam[]
      local liquidationLimits, borrowBalances = {}, {}

      -- symbols to sync
      ---@type string[]
      local symbols = {}

      -- incoming and outgoing token data
      ---@type TokenData, TokenData
      local inTokenData, outTokenData = {}, {}

      -- the total collateral of the desired reward token
      -- in the user's position for the reward token
      local availableRewardQty = zero
      local availableLiquidateQty = zero

      -- check if the user has any open positions (active loans)
      local hasOpenPosition = false

      -- populate capacities, symbols, incoming/outgoing token data and collateral qty
      for _, pos in ipairs(positions) do
        local symbol = pos.Tags["Collateral-Ticker"]
        local denomination = tonumber(pos.Tags["Collateral-Denomination"]) or 0

        -- convert quantities
        local liquidationLimit = bint(pos.Tags["Liquidation-Limit"] or 0)
        local borrowBalance = bint(pos.Tags["Borrow-Balance"] or 0)

        if pos.From == oTokensParticipating.liquidated then
          inTokenData = { ticker = symbol, denomination = denomination }
          availableLiquidateQty = borrowBalance
        elseif pos.From == oTokensParticipating.reward then
          outTokenData = { ticker = symbol, denomination = denomination }
          availableRewardQty = bint(pos.Tags.Collateralization or 0)
        end

        -- only sync if there is a position
        if bint.ult(zero, borrowBalance) or bint.ult(zero, liquidationLimit) then
          table.insert(symbols, symbol)
          table.insert(borrowBalances, {
            ticker = symbol,
            quantity = borrowBalance,
            denomination = denomination
          })
          table.insert(liquidationLimits, {
            ticker = symbol,
            quantity = liquidationLimit,
            denomination = denomination
          })
        end

        -- update user position indicator
        if bint.ult(zero, borrowBalance) then
          hasOpenPosition = true
        end
      end

      assert(
        inTokenData.ticker ~= nil and inTokenData.denomination ~= nil,
        "Incoming token data not found"
      )
      assert(
        outTokenData.ticker ~= nil and outTokenData.denomination ~= nil,
        "Outgoing token data not found"
      )
      assert(
        bint.ult(zero, availableRewardQty),
        "No available reward quantity"
      )
      assert(
        bint.ult(zero, availableLiquidateQty),
        "No available liquidate quantity"
      )

      -- check if the user has any open positions
      if not hasOpenPosition then
        -- remove from auctions if present
        liquidations.removeAuction(target)

        -- error and trigger refund
        error("User does not have an active loan")
      end

      -- ensure "liquidation-limit / borrow-balance < 1"
      -- this means that the user is eligible for liquidation
      local totalLiquidationLimit = utils.reduce(
        function (acc, curr) return acc + curr.value end,
        zero,
        oracle.getValues(prices, liquidationLimits)
      )
      local totalBorrowBalance = utils.reduce(
        function (acc, curr) return acc + curr.value end,
        zero,
        oracle.getValues(prices, borrowBalances)
      )

      assert(
        bint.ult(totalLiquidationLimit, totalBorrowBalance),
        "Target not eligible for liquidation"
      )

      -- get token quantities
      local inQty = bint(msg.Tags.Quantity)

      -- market value of the liquidation
      local marketValueInQty = oracle.getValueInToken(
        {
          ticker = inTokenData.ticker,
          quantity = inQty,
          denomination = inTokenData.denomination
        },
        outTokenData,
        prices
      )

      -- make sure that the user's position is enough to pay the liquidator
      -- (at least the market value of the tokens)
      assert(
        bint.ule(marketValueInQty, availableRewardQty),
        "The user does not have enough tokens in their position for this liquidation"
      )

      -- apply auction
      local discount = tokens.getDiscount(target)

      -- update the expected reward quantity using the discount
      local expectedRewardQty = marketValueInQty

      if discount > 0 then
        expectedRewardQty = bint.udiv(
          expectedRewardQty * bint(100 * PrecisionFactor + discount),
          bint(100 * PrecisionFactor)
        )
      end

      -- if the discount is higher than the position in the
      -- reward token, we need to update it with the maximum
      -- possible amount
      if bint.ult(availableRewardQty, expectedRewardQty) then
        expectedRewardQty = availableRewardQty
      end

      -- the minimum quantity expected by the user
      local minExpectedRewardQty = bint(msg.Tags["X-Min-Expected-Quantity"] or 0)

      -- make sure the user is receiving at least
      -- the minimum amount of tokens they're expecting
      assert(
        bint.ule(minExpectedRewardQty, expectedRewardQty),
        "Could not meet the defined slippage"
      )

      -- check liquidation queue
      assert(
        not utils.includes(target, LiquidationQueue),
        "User is already queued for liquidation"
      )

      -- whether or not to remove the auction after this liquidation is complete.
      -- this checks if the position becomes healthy after the liquidation
      local removeWhenDone = bint.ule(
        totalBorrowBalance - oracle.getValue(prices, bint.min(inQty, availableLiquidateQty), inTokenData.ticker, inTokenData.denomination),
        totalLiquidationLimit - oracle.getValue(prices, expectedRewardQty, outTokenData.ticker, outTokenData.denomination)
      )

      return "", expectedRewardQty, oTokensParticipating, removeWhenDone
    end)

    -- check if liquidation is possible
    if not success then
      -- signal error
      ao.send({
        Target = liquidator,
        Action = "Liquidate-Error",
        Error = string.gsub(errorMsg, "%[[%w_.\" ]*%]:%d*: ", "")
      })

      -- refund
      return ao.send({
        Target = msg.From,
        Action = "Transfer",
        Quantity = msg.Tags.Quantity,
        Recipient = liquidator
      })
    end

    -- since a liquidation is possible for the target
    -- we add it to the list of discovered auctions
    liquidations.addAuction(target, msg.Timestamp)

    -- queue the liquidation at this point, because
    -- the user position has been checked, so the liquidation is valid
    -- we don't want anyone to be able to liquidate from this point
    table.insert(LiquidationQueue, target)

    -- TODO: timeout here? (what if this doesn't return in time, the liquidation remains in a pending state)
    -- TODO: this timeout can be done with a Handler that removed this coroutine

    -- liquidation reference to identify the result
    -- (we cannot use .receive() here, since both the target
    -- and the default response reference will change, because
    -- of the chained messages)
    local liquidationReference = msg.Id .. "-" .. liquidator

    -- liquidate the loan
    ao.send({
      Target = liquidatedToken,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = oTokensParticipating.liquidated,
      ["X-Action"] = "Liquidate-Borrow",
      ["X-Liquidator"] = liquidator,
      ["X-Liquidation-Target"] = target,
      ["X-Reward-Market"] = oTokensParticipating.reward,
      ["X-Reward-Quantity"] = tostring(expectedRewardQty),
      ["X-Liquidation-Reference"] = liquidationReference
    })

    -- wait for result
    local loanLiquidationRes = Handlers.receive({
      From = oTokensParticipating.liquidated,
      ["Liquidation-Reference"] = liquidationReference
    })

    -- remove from queue
    LiquidationQueue = utils.filter(
      function (v) return v ~= target end,
      LiquidationQueue
    )

    -- check loan liquidation result
    -- (at this point, we do not need to refund the user
    -- because the oToken process handles that)
    if loanLiquidationRes.Tags.Error or loanLiquidationRes.Tags.Action ~= "Liquidate-Borrow-Confirmation" then
      return ao.send({
        Target = liquidator,
        Action = "Liquidate-Error",
        Error = loanLiquidationRes.Tags.Error
      })
    end

    -- if the auction is done (no more loans to liquidate)
    -- we need to remove it from the discovered auctions
    if removeWhenDone then
      liquidations.removeAuction(target)
    end

    -- send confirmation to the liquidator
    ao.send({
      Target = liquidator,
      Action = "Liquidate-Confirmation",
      ["Liquidation-Target"] = target,
      ["From-Quantity"] = msg.Tags.Quantity,
      ["From-Token"] = liquidatedToken,
      ["To-Quantity"] = tostring(expectedRewardQty),
      ["To-Token"] = rewardToken
    })

    -- send notice to the target
    ao.send({
      Target = target,
      Action = "Liquidate-Notice",
      ["From-Quantity"] = msg.Tags.Quantity,
      ["To-Quantity"] = tostring(expectedRewardQty)
    })
  end
)

Handlers.add(
  "add-collateral-queue",
  function (msg)
    if msg.Action ~= "Add-To-Queue" then return false end
    return utils.find(
      function (t) return t.oToken == msg.From end,
      Tokens
    ) ~= nil
  end,
  function (msg)
    local user = msg.Tags.User

    -- validate address
    if not assertions.isAddress(user) then
      return msg.reply({ Error = "Invalid user address" })
    end

    -- check if the user has already been added
    if utils.includes(user, CollateralQueue) or utils.includes(user, LiquidationQueue) or UpdateInProgress then
      return msg.reply({ Error = "User already queued" })
    end

    -- add to queue
    table.insert(CollateralQueue, user)

    msg.reply({ ["Queued-User"] = user })
  end
)

Handlers.add(
  "remove-collateral-queue",
  function (msg)
    if msg.Action ~= "Remove-From-Queue" then return false end
    return utils.find(
      function (t) return t.oToken == msg.From end,
      Tokens
    ) ~= nil
  end,
  function (msg)
    local user = msg.Tags.User

    -- validate address
    if not assertions.isAddress(user) then
      return msg.reply({ Error = "Invalid user address" })
    end

    -- filter out user
    CollateralQueue = utils.filter(
      function (v) return v ~= user end,
      CollateralQueue
    )

    msg.reply({ ["Unqueued-User"] = user })
  end
)

Handlers.add(
  "check-queue",
  { Action = "Check-Queue-For" },
  function (msg)
    local user = msg.Tags.User

    -- validate address
    if not assertions.isAddress(user) then
      return msg.reply({ ["In-Queue"] = "false" })
    end

    -- the user is queued if they're either in the collateral
    -- or the liquidation queues
    return msg.reply({
      ["In-Queue"] = json.encode(
        utils.includes(user, CollateralQueue) or
        utils.includes(user, LiquidationQueue)
      )
    })
  end
)

Handlers.add(
  "get-auctions",
  { Action = "Get-Auctions" },
  function (msg)
    msg.reply({
      ["Initial-Discount"] = tostring(MaxDiscount),
      ["Final-Discount"] = tostring(MinDiscount),
      ["Discount-Interval"] = tostring(DiscountInterval),
      Data = next(Auctions) ~= nil and json.encode(Auctions) or "{}"
    })
  end
)

-- Removes an auction with a cooldown
---@param target string Auction target address
function liquidations.removeAuction(target)
  if Auctions[target] == nil then return end

  local removeAuctionAfter = Timestamp + 1000 * 60 * 60 * 3 -- in 3 hours
  local handlerName = "auctions-remove-" .. target

  Handlers.remove(handlerName)
  Handlers.once(
    handlerName,
    function (msg)
      if msg.Timestamp > removeAuctionAfter then
        return "continue"
      end
      return false
    end,
    function () Auctions[target] = nil end
  )
end

-- Adds a newly discovered auction
---@param target string Auction target address
---@param discovered number Discovery timestamp
function liquidations.addAuction(target, discovered)
  -- delete handler that would remove the auction and add auction
  Handlers.remove("auctions-remove-" .. target)

  -- add discovery date if the user isn't already in auctions
  if Auctions[target] == nil then
    Auctions[target] = discovered
  end
end

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function assertions.isAddress(addr)
  if type(addr) ~= "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "^[A-z0-9_-]+$") == nil then return false end

  return true
end

-- Check if token is supported by the protocol
-- (token supports aos 2.0 replies and replies with a proper info response)
-- Returns if the token is supported and the token info
---@param addr string Token address
function tokens.isSupported(addr)
  -- send info request
  ao.send({
    Target = addr,
    Action = "Info",
  })

  -- wait for proper response
  local res = Handlers.receive({
    From = addr,
    Ticker = "^.+$",
    Name = "^.+$",
    Denomination = "^.+$"
  })

  local repliesSupported = res.Tags["X-Reference"] ~= nil

  local denomination = tonumber(res.Tags.Denomination)
  local validDenomination = denomination ~= nil and
    denomination == denomination // 1 and
    denomination > 0 and
    denomination <= 18

  return repliesSupported and validDenomination, res
end

-- Checks if an input is not inf or nan
---@param val number Input to check
function assertions.isValidNumber(val)
  return val == val and val % 1 == 0
end

-- Validates if the provided value can be parsed as a Bint
---@param val any Value to validate
---@return boolean
function assertions.isBintRaw(val)
  local success, result = pcall(
    function ()
      -- check if the value is convertible to a Bint
      if type(val) ~= "number" and type(val) ~= "string" and not bint.isbint(val) then
        return false
      end

      -- check if the val is an integer and not infinity, in case if the type is number
      if type(val) == "number" and not assertions.isValidNumber(val) then
        return false
      end

      return true
    end
  )

  return success and result
end

-- Verify if the provided value can be converted to a valid token quantity
---@param qty any Raw quantity to verify
---@return boolean
function assertions.isTokenQuantity(qty)
  local numVal = tonumber(qty)
  if not numVal or numVal <= 0 then return false end
  if not assertions.isBintRaw(qty) then return false end
  if type(qty) == "number" and qty < 0 then return false end
  if type(qty) == "string" and string.sub(qty, 1, 1) == "-" then
    return false
  end

  return true
end

-- Get current discount for a target
---@param target string Target address
function tokens.getDiscount(target)
  -- apply auction model
  -- time passed in milliseconds since the discovery of this auction
  local timePassed = Timestamp - (Auctions[target] or Timestamp)

  -- if the time passed is higher than the discount interval
  -- we reached the minimum discount price, so we
  -- set the time passed to the corresponding interval
  if timePassed > DiscountInterval then
    timePassed = DiscountInterval
  end

  -- current discount percentage:
  -- a linear function of the time passed,
  -- the discount becomes 0 when the discount
  -- interval is over
  local discount = math.max((DiscountInterval - timePassed) * MaxDiscount * PrecisionFactor // DiscountInterval, MinDiscount)

  return discount
end

function scheduler.schedule(...)
  -- get the running handler's thread
  local thread = coroutine.running()

  -- repsonse handler
  local responses = {}
  local messages = {...}

  -- if there are no messages to be sent, we don't do anything
  if #messages == 0 then return {} end

  ---@type HandlerFunction
  local function responseHandler(msg)
    table.insert(responses, msg)

    -- continue execution when all responses are back
    if #responses == #messages then
      -- if the result of the resumed coroutine is an error, then we should bubble it up to the process
      local _, success, errmsg = coroutine.resume(thread, responses)

      assert(success, errmsg)
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
  return coroutine.yield({ From = messages[#messages], ["X-Reference"] = tostring(ao.reference) })
end

-- Get price data for an array of token symbols
function oracle.sync()
  ---@type RawPrices
  local res = {}

  -- all collateral tickers
  local symbols = utils.map(
    ---@param f Friend
    function (f) return f.ticker end,
    Tokens
  )

  -- no tokens to sync
  if #symbols == 0 then return res end

  ---@type string|nil
  local rawData = ao.send({
    Target =  Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode(symbols)
  }).receive().Data

  -- no price data returned
  if not rawData or rawData == "" then return res end

  ---@type boolean, OracleData
  local parsed, data = pcall(json.decode, rawData)

  assert(parsed, "Could not parse oracle data")

  for ticker, p in pairs(data) do
    -- only add data if the timestamp is up to date
    if p.t + MaxOracleDelay >= Timestamp then
      res[ticker] = {
        price = p.v,
        timestamp = p.t
      }
    end
  end

  return res
end

-- Get the value of a single quantity
---@param rawPrices RawPrices Raw price data
---@param quantity Bint Token quantity
---@param ticker string Token ticker
---@param denomination number Token denomination
function oracle.getValue(rawPrices, quantity, ticker, denomination)
  local res = oracle.getValues(rawPrices, {
    { ticker = ticker, denomination = denomination, quantity = quantity }
  })

  assert(res[1] ~= nil, "No price calculated")

  return res[1].value
end

-- Get the value of quantities of the provided assets. The function
-- will only provide up to date values, outdated and nil values will be
-- filtered out
---@param rawPrices RawPrices Raw results from the oracle
---@param quantities PriceParam[] Token quantities
function oracle.getValues(rawPrices, quantities)
  ---@type { ticker: string, value: Bint }[]
  local results = {}

  local one = bint.one()
  local zero = bint.zero()

  for _, v in ipairs(quantities) do
    if not v.quantity then v.quantity = one end
    if not bint.eq(v.quantity, zero) then
      -- make sure the oracle returned the price
      assert(rawPrices[v.ticker] ~= nil, "No price returned from the oracle for " .. v.ticker)

      -- the value of the quantity
      -- (USD price value is denominated for precision,
      -- but the result needs to be divided according
      -- to the underlying asset's denomination,
      -- because the price data is for the non-denominated
      -- unit)
      local value = bint.udiv(
        v.quantity * oracle.getUSDDenominated(rawPrices[v.ticker].price),
        -- optimize performance by repeating "0" instead of a power operation
        bint("1" .. string.rep("0", v.denomination))
      )

      -- add data
      table.insert(results, {
        ticker = v.ticker,
        value = value
      })
    else
      table.insert(results, {
        ticker = v.ticker,
        value = zero
      })
    end
  end

  return results
end

-- Get the value of one token quantity in another
-- token quantity
---@param from { ticker: string, quantity: Bint, denomination: number } From token ticker, quantity and denomination
---@param to TokenData Target token ticker and denomination
---@param rawPrices RawPrices Pre-fetched prices
---@return Bint
function oracle.getValueInToken(from, to, rawPrices)
  -- prices
  local fromPrice = oracle.getUSDDenominated(rawPrices[from.ticker].price)
  local toPrice = oracle.getUSDDenominated(rawPrices[to.ticker].price)

  -- get value of the "from" token quantity in USD with extra precision
  local usdValue = bint.udiv(
    from.quantity * fromPrice,
    bint("1" .. string.rep("0", from.denomination))
  )

  -- convert usd value to the token quantity
  -- accounting for the denomination
  return bint.udiv(
    usdValue * bint("1" .. string.rep("0", to.denomination)),
    toPrice
  )
end

-- Get the precision used for USD biginteger values
function oracle.getUSDDenomination() return 12 end

-- Get the fractional part's length
---@param val number Full number
function oracle.getFractionsCount(val)
  -- check if there is a fractional part 
  -- by trying to find it with a pattern
  local fractionalPart = string.match(oracle.floatToString(val), "%.(.*)")

  if not fractionalPart then return 0 end

  -- get the length of the fractional part
  return string.len(fractionalPart)
end

-- Get a USD value in a 12 denominated form
---@param val number USD value as a floating point number
---@return Bint
function oracle.getUSDDenominated(val)
  local denominator = oracle.getUSDDenomination()

  -- remove decimal point
  local denominated = string.gsub(oracle.floatToString(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = oracle.getFractionsCount(val)

  local wholeDigits = string.len(denominated) - fractions
  denominated = denominated .. string.rep("0", denominator)
  denominated = string.sub(denominated, 1, wholeDigits + denominator)

  return bint(denominated)
end

-- Convert a lua number to a string
---@param val number The value to convert
function oracle.floatToString(val)
  return string.format("%.17f", val):gsub("0+$", ""):gsub("%.$", "")
end
