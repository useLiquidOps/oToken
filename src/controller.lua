local coroutine = require "coroutine"
local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"
local assertions = {}
local scheduler = {}
local oracle = {}
local tokens = {}

-- oToken module ID
Module = Module or "C6CQfrL29jZ-LYXV2lKn09d3pBIM6adDFwWqh2ICikM"

-- oracle id and tolerance
Oracle = Oracle or "4fVi8P-xSRWxZ0EE0EpltDe8WJJvcD9QyFXMqfk-1UQ"
MaxOracleDelay = MaxOracleDelay or 1200000

-- liquidops logo tx id
ProtocolLogo = ProtocolLogo or ""

-- token - oToken map
---@type table<string, string>
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

-- maximum discount that can be applied to a loan in percentages
MaxDiscount = MaxDiscount or 10

-- the period till the auction reaches the minimum discount (market price)
DiscountInterval = DiscountInterval or 1000 * 60 * 60 -- 1 hour

---@alias TokenData { ticker: string, denomination: number }

Handlers.add(
  "sync-timestamp",
  function () return "continue" end,
  function (msg) Timestamp = msg.Timestamp end
)

Handlers.add(
  "sync-auctions",
  { Action = "Cron" },
  function (msg)
    -- get all user positions
    ---@type Message[]
    local rawPositions = scheduler.schedule(table.unpack(utils.map(
      function (id) return { Target = id, Action = "Positions" } end,
      utils.values(Tokens)
    )))

    -- fetch prices
    local rawPrices = oracle.getPrices(utils.map(
      ---@param p Message
      function (p) return p.Tags["Collateral-Ticker"] end,
      rawPositions
    ))

    -- protocol positions in USD
    ---@type table<string, { capacity: Bint, usedCapacity: Bint }>
    local allPositions = {}
    local zero = bint.zero()

    -- add positions
    for _, market in ipairs(rawPositions) do
      ---@type table<string, { Capacity: string, ["Used-Capacity"]: string, ["Total-Collateral"]: string }>
      local marketPositions = json.decode(market.Data)
      local ticker = market.Tags["Collateral-Ticker"]
      local denomination = tonumber(market.Tags["Collateral-Denomination"]) or 0

      -- add each position in the market by their usd value
      for address, position in pairs(marketPositions) do
        local posCapacity = bint(position.Capacity)
        local posUsedCapacity = bint(position["Used-Capacity"])

        local hasCollateral = bint.ult(zero, posCapacity)
        local hasLoan = bint.ult(zero, posUsedCapacity)

        if hasCollateral or hasLoan then
          allPositions[address] = allPositions[address] or { capacity = zero, usedCapacity = zero }

          -- add capacity
          if hasCollateral then
            allPositions[address].capacity = allPositions[address].capacity + oracle.getValue(
              rawPrices,
              posCapacity,
              ticker,
              denomination
            )
          end

          -- add used capacity
          if hasLoan then
            allPositions[address].usedCapacity = allPositions[address].usedCapacity + oracle.getValue(
              rawPrices,
              posUsedCapacity,
              ticker,
              denomination
            )
          end
        end
      end
    end

    -- now find the positions that can be auctioned
    -- and update existing auctions
    for address, position in pairs(allPositions) do
      -- check if the position can be liquidated
      if bint.ult(position.capacity, position.usedCapacity) then
        -- if the liquidation has just been discovered, add it to the auctions
        if Auctions[address] == nil then
          Auctions[address] = msg.Timestamp
        end
      elseif Auctions[address] ~= nil then
        -- remove auction, it is no longer necessary
        Auctions[address] = nil
      end
    end
  end
)

Handlers.add(
  "list",
  { From = ao.env.Process.Id, Action = "List" },
  function (msg)
    -- token to be listed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )

    -- check configuration
    assert(
      tonumber(msg.Tags["Collateral-Factor"]) ~= nil,
      "Invalid collateral factor"
    )
    assert(
      tonumber(msg.Tags["Liquidation-Threshold"]) ~= nil,
      "Invalid liquidation threshold"
    )
    assert(
      tonumber(msg.Tags["Base-Rate"]) ~= nil,
      "Invalid base rate"
    )
    assert(
      tonumber(msg.Tags["Init-Rate"]) ~= nil,
      "Invalid init rate"
    )

    -- check if token is supported
    local supported, info = tokens.isSupported(token)

    assert(supported, "Token not supported by the protocol")

    -- spawn logo
    --local logo = tokens.spawnProtocolLogo(info.Tags.Logo)
    local logo = info.Tags.Logo

    -- the oToken configuration
    local config = {
      ["Collateral-Id"] = token,
      ["Collateral-Ticker"] = info.Tags.Ticker,
      ["Collateral-Name"] = info.Tags.Name,
      ["Collateral-Denomination"] = info.Tags.Denomination,
      ["Collateral-Factor"] = msg.Tags["Collateral-Factor"],
      ["Liquidation-Threshold"] = msg.Tags["Liquidation-Threshold"],
      ["Base-Rate"] = msg.Tags["Base-Rate"],
      ["Init-Rate"] = msg.Tags["Init-Rate"],
      Oracle = Oracle,
      ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
      Friends = next(Tokens) ~= nil and json.encode(utils.values(Tokens)) or "[]",
      Logo = logo,
      Authority = ao.authorities[1]
    }

    -- spawn new oToken process
    local spawnResult = ao.spawn(Module, config).receive()

    -- notify all other tokens
    for _, oToken in pairs(Tokens) do
      ao.send({
        Target = oToken,
        Action = "Add-Friend",
        Friend = spawnResult.Tags.Process
      })
    end

    -- add token to tokens list
    Tokens[token] = spawnResult.Tags.Process

    msg.reply({
      Action = "Token-Listed",
      Token = token,
      ["Spawned-Id"] = spawnResult.Tags.Process,
      Data = json.encode(config)
    })
  end
)

Handlers.add(
  "unlist",
  { From = ao.env.Process.Id, Action = "Unlist" },
  function (msg)
    -- token to be removed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )
    assert(Tokens[token] ~= nil, "Token is not listed")

    -- id of the oToken for this token
    local oToken = Tokens[token]

    -- unlist
    Tokens[token] = nil

    -- notify all other tokens
    for _, friend in pairs(Tokens) do
      ao.send({
        Target = friend,
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
  "get-tokens",
  { Action = "Get-Tokens" },
  function (msg)
    msg.reply({
      Data = json.encode(Tokens)
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
    -- the user has to have a posisition in this token
    local rewardToken = msg.Tags["X-Reward-Token"]

    -- prepare liquidation, check required environment
    local success, errorMsg, expectedRewardQty, removeWhenDone = pcall(function ()
      assert(
        assertions.isAddress(target) and target ~= liquidator,
        "Invalid liquidation target"
      )
      assert(
        Tokens[liquidatedToken] ~= nil,
        "Cannot liquidate the incoming token as it is not listed"
      )
      assert(
        Tokens[rewardToken] ~= nil,
        "Cannot liquidate for the reward token as it is not listed"
      )

      -- check user position
      ---@type Message[]
      local positions = scheduler.schedule(table.unpack(utils.map(
        function (id) return { Target = id, Action = "Position", Recipient = target } end,
        utils.values(Tokens)
      )))

      -- check liquidation queue
      assert(
        not utils.includes(target, LiquidationQueue),
        "User is already queued for liquidation"
      )

      -- get tokens that need a price fetch
      local zero = bint.zero()

      ---@type PriceParam[], PriceParam[]
      local capacities, usedCapacities = {}, {}

      -- symbols to sync
      ---@type string[]
      local symbols = {}

      -- incoming and outgoing token data
      ---@type TokenData, TokenData
      local inTokenData, outTokenData = {}, {}

      -- the total collateral in the user's position
      -- for the reward token
      local availableRewardQty = zero

      -- check if the user has any open positions (active loans)
      local hasOpenPosition = false

      -- populate capacities, symbols, incoming/outgoing token data and collateral qty
      for _, pos in ipairs(positions) do
        local symbol = pos.Tags["Collateral-Ticker"]
        local denomination = tonumber(pos.Tags["Collateral-Denomination"]) or 0

        if pos.From == liquidatedToken then
          inTokenData = { ticker = symbol, denomination = denomination }
        elseif pos.From == rewardToken then
          outTokenData = { ticker = symbol, denomination = denomination }
          availableRewardQty = bint(pos.Tags["Total-Collateral"])
        end

        -- convert quantities
        local capacity = bint(pos.Tags.Capacity)
        local usedCapacity = bint(pos.Tags["Used-Capacity"])

        -- only sync if there is a position
        if bint.ult(zero, capacity) or bint.ult(zero, usedCapacity) then
          table.insert(symbols, symbol)
          table.insert(capacities, {
            ticker = symbol,
            quantity = capacity,
            denomination = denomination
          })
          table.insert(usedCapacities, {
            ticker = symbol,
            quantity = usedCapacity,
            denomination = denomination
          })
        end

        -- update user position indicator
        if bint.ult(zero, usedCapacity) then
          hasOpenPosition = true
        end
      end

      -- check if the user has any open positions
      if not hasOpenPosition then
        -- remove from auctions if present
        Auctions[target] = nil

        -- error and trigger refund
        error("User does not have an active loan")
      end

      -- fetch prices
      local prices = oracle.getPrices(symbols)

      -- ensure health factor is <1 (eligible for liquidation)
      -- (health factor = capacity / usedCapacity)
      -- the values below are in USD
      local totalCapacity = utils.reduce(
        function (acc, curr) return acc + curr.value end,
        zero,
        oracle.getValues(prices, capacities)
      )
      local totalUsedCapacity = utils.reduce(
        function (acc, curr) return acc + curr.value end,
        zero,
        oracle.getValues(prices, usedCapacities)
      )

      assert(
        bint.ult(totalCapacity, totalUsedCapacity),
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

      -- apply dutch auction model
      -- time passed in milliseconds since the discovery of this auction
      local timePassed = msg.Timestamp - (Auctions[target] or msg.Timestamp)

      -- if the time passed is higher than the discount,
      -- we reached the minimum discount price, so we
      -- set the time passed to the corresponding interval
      if timePassed > DiscountInterval then
        timePassed = DiscountInterval
      end

      -- currnet discount:
      -- a linear function of the time passed,
      -- the discount becomes 0 when the discount
      -- interval is over
      local discount = (DiscountInterval - timePassed) * MaxDiscount // DiscountInterval

      -- update the expected reward quantity using the discount
      local expectedRewardQty = marketValueInQty

      if discount > 0 then
        expectedRewardQty = oracle.getValueInToken(
          {
            ticker = inTokenData.ticker,
            quantity = bint.udiv(
              inQty * bint(100 - discount),
              bint(100)
            ),
            denomination = inTokenData.denomination
          },
          outTokenData,
          prices
        )
      end

      -- if the discount is higher than the position in the
      -- reward token, we need to update it with the maximum
      -- possible amount
      if bint.ult(availableRewardQty, expectedRewardQty) then
        expectedRewardQty = availableRewardQty
      end

      -- check liquidation queue again
      -- in case a liquidation has been queued
      -- while fetching positions
      assert(
        not utils.includes(target, LiquidationQueue),
        "User is already queued for liquidation"
      )

      -- whether or not to remove the auction after
      -- this liquidation is complete
      -- (the auction needs to be removed if there
      -- will be no loans left when the liquidation is complete)
      local removeWhenDone = utils.find(
        ---@param c PriceParam
        function (c)
          if not c.quantity then return false end

          -- the auction should not be removed, if the
          -- liquidation does not pay for the entire
          -- loan
          if c.ticker == inTokenData.ticker then
            return bint.ult(inQty, c.quantity)
          end

          -- the auction should not be removed if the
          -- target has an active loan in another asset
          -- besides the one that is liquidated currently
          return bint.ult(zero, c.quantity)
        end,
        usedCapacities
      ) ~= nil

      return "", expectedRewardQty, removeWhenDone
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
    -- (if not already present)
    if not Auctions[target] then
      Auctions[target] = msg.Timestamp
    end

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
      Recipient = Tokens[liquidatedToken],
      ["X-Action"] = "Liquidate-Borrow",
      ["X-Liquidator"] = liquidator,
      ["X-Liquidation-Target"] = target,
      ["X-Reward-Market"] = Tokens[rewardToken],
      ["X-Reward-Quantity"] = tostring(expectedRewardQty),
      ["X-Liquidation-Reference"] = liquidationReference
    })

    -- wait for result
    local loanLiquidationRes = Handlers.receive({
      From = Tokens[liquidatedToken],
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
      Auctions[target] = nil
    end

    -- send confirmation to the liquidator
    ao.send({
      Target = liquidator,
      Action = "Liquidate-Confirmation",
      ["Liquidation-Target"] = target,
      ["From-Quantity"] = msg.Tags.Quantity,
      ["To-Quantity"] = tostring(expectedRewardQty)
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

    -- more efficient than using utils for this
    for _, v in pairs(Tokens) do
      if v == msg.From then return true end
    end

    return false
  end,
  function (msg)
    local user = msg.Tags.User

    -- validate address
    if not assertions.isAddress(user) then
      return msg.reply({ Error = "Invalid user address" })
    end

    -- check if the user has already been added
    if utils.includes(user, CollateralQueue) or utils.includes(user, LiquidationQueue) then
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

    -- more efficient than using utils for this
    for _, v in pairs(Tokens) do
      if v == msg.From then return true end
    end

    return false
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
      Data = next(Auctions) ~= nil and json.encode(Auctions) or "{}"
    })
  end
)

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function assertions.isAddress(addr)
  if not type(addr) == "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "[A-z0-9_-]+") == nil then return false end

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

-- Spawn a LiquidOps themed logo for the oToken
-- (if the collateral doesn't have a logo, the protocol
-- will use the liquidops logo by default)
---@param collateralLogo string? The logo of the collateral token
function tokens.spawnProtocolLogo(collateralLogo)
  if not collateralLogo then return ProtocolLogo end

  -- the base logo on two parts
  local logoPart1 = '<svg width="209" height="209" viewBox="0 0 209 209" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><path fill-rule="evenodd" clip-rule="evenodd" d="M104.338 167.45C69.4822 167.45 41.2261 139.194 41.2261 104.338C41.2261 69.4822 69.4822 41.2261 104.338 41.2261C139.194 41.2261 167.45 69.4822 167.45 104.338C167.45 139.194 139.194 167.45 104.338 167.45Z" fill="white"/><path fill-rule="evenodd" clip-rule="evenodd" d="M0.0258105 104.338C0.025808 161.948 46.7279 208.65 104.338 208.65C161.948 208.65 208.65 161.948 208.65 104.338C208.65 46.728 161.948 0.0258769 104.338 0.0258743C46.7279 0.0258718 0.025813 46.728 0.0258105 104.338Z" fill="url(#paint0_radial_1139_423)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M8.14144 144.709C26.0007 187.415 70.2136 213.262 116.097 207.999C101.792 198.058 31.5666 127.163 98.1277 96.6245C170.951 63.2132 166.399 24.8374 149.014 10.0751C127.427 -0.168817 102.228 -3.08861 77.34 3.58023C57.2243 8.97022 40.0649 19.8861 27.0574 34.257C14.6366 48.2947 5.9814 65.395 2.1366 83.3465C-0.233773 94.8415 -0.68376 106.868 1.04746 118.976C1.64542 122.737 2.47999 126.472 3.56051 130.162C4.69973 135.191 6.24463 140.047 8.14144 144.709Z" fill="url(#paint1_linear_1139_423)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M147.996 9.59888C163.381 20.0038 201.307 50.7506 136.617 87.8522C65.7443 128.5 125.078 191.493 164.844 189.344C199.306 164.807 216.688 120.605 205.096 77.3404C196.749 46.1915 175.153 22.1313 147.996 9.59888Z" fill="url(#paint2_linear_1139_423)"/><path d="M103.955 166.453C138.12 166.453 165.816 138.757 165.816 104.592C165.816 70.4275 138.12 42.7314 103.955 42.7314C69.7903 42.7314 42.0941 70.4275 42.0941 104.592C42.0941 138.757 69.7903 166.453 103.955 166.453Z" fill="white"/><path d="M103.955 166.453C138.12 166.453 165.816 138.757 165.816 104.592C165.816 70.4275 138.12 42.7314 103.955 42.7314C69.7903 42.7314 42.0941 70.4275 42.0941 104.592C42.0941 138.757 69.7903 166.453 103.955 166.453Z" fill="url(#pattern0_1139_423)"/><defs><pattern id="pattern0_1139_423" patternContentUnits="objectBoundingBox" width="1" height="1"><use xlink:href="#image0_1139_423" transform="scale(0.0025)"/></pattern><radialGradient id="paint0_radial_1139_423" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(104.338 104.338) rotate(-29.6192) scale(135.925 130.152)"><stop offset="0.5" stop-color="#B8B8FF"/><stop offset="1" stop-color="#DCDCFF"/></radialGradient><linearGradient id="paint1_linear_1139_423" x1="79.895" y1="265.291" x2="79.895" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><linearGradient id="paint2_linear_1139_423" x1="267.473" y1="120.937" x2="44.7973" y2="120.937" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><image id="image0_1139_423" width="400" height="400" xlink:href="'
  local logoPart2 = '" preserveAspectRatio="xMidYMid slice"/></defs></svg>'

  -- message that spawns the logo
  -- we're sending this to ourselves
  ---@type Message
  local spawnedImage = ao.send({
    Target = ao.id,
    Action = "Spawn-Logo",
    ["Content-Type"] = "image/svg+xml",
    Data = logoPart1 .. "/" .. collateralLogo .. logoPart2
  }).receive(ao.id)

  return spawnedImage.Id
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
---@param symbols string[] Token symbols
function oracle.getPrices(symbols)
  ---@type RawPrices
  local res = {}

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

  ---@type OracleData
  local data = json.decode(rawData)

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
  -- accouting for the denomination
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
  local fractionalPart = string.match(tostring(val), "%.(.*)")

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
  local denominated = string.gsub(tostring(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = oracle.getFractionsCount(val)

  if fractions < denominator then
    denominated = denominated .. string.rep("0", denominator - fractions)
  elseif fractions > denominator then
    -- get the count of the integer part's digits
    local wholeDigits = string.len(denominated) - fractions

    denominated = string.sub(denominated, 1, wholeDigits + denominator)
  end

  return bint(denominated)
end
