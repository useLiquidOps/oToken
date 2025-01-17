local coroutine = require "coroutine"
local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"
local assertions = {}
local scheduler = {}
local oracle = {}
local tokens = {}

-- oToken module ID
Module = ""

-- oracle id and tolerance
Oracle = ""
MaxOracleDelay = 1200000

-- liquidops logo tx id
ProtocolLogo = ""

-- token - oToken map
---@type table<string, string>
Tokens = {}

-- TODO: should queues have timeouts?

-- queue for operations in oTokens that involve
-- the collateral/collateralization
---@type string[]
CollateralQueue = {}

-- queue for liquidations
LiquidationQueue = {}

-- current timestamp
Timestamp = 0

Handlers.add(
  "sync-timestamp",
  function () return "continue" end,
  function (msg) Timestamp = msg.Timestamp end
)

Handlers.add(
  "list",
  { From = ao.id, Action = "List" },
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
    local logo = tokens.spawnProtocolLogo(info.Tags.Logo)

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
      Friends = json.encode(utils.values(Tokens)),
      Logo = logo
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
  { From = ao.id, Action = "Unlist" },
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

    assert(
      assertions.isAddress(target),
      "Invalid liquidation target"
    )

    -- token to be liquidated, currently loaned to the target
    -- (the token that is paying for the loan = transferred token)
    local liquidatedToken = msg.From

    assert(
      Tokens[liquidatedToken] ~= nil,
      "Cannot liquidate the incoming token as it is not listed"
    )

    -- the token that the liquidator will earn for
    -- paying off the loan
    -- the user has to have a posisition in this token
    local rewardToken = msg.Tags["X-Reward-Token"]

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
    -- (here the queues should all be synced)
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

    -- populate capacities, symbols
    for _, pos in ipairs(positions) do
      local symbol = pos.Tags["Collateral-Ticker"]
      local denomination = tonumber(pos.Tags["Collateral-Denomination"])

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
    end

    -- fetch prices
    local prices = oracle.getPrices(symbols)

    -- ensure health factor is >1
    -- (health factor = capacity / usedCapacity)
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
    local expectedRewardQty = oracle.getValueInToken(
      -- TODO
      { ticker = "", quantity = inQty, denomination = "" },
      { ticker = "", denomination = "" },
      prices
    )

    -- make sure that the user's position is enough to pay the liquidator
    assert(
      bint.ule(, bint(pos.Tags["Total-Collateral"])),
      "The user does not have enough tokens in their position for this liquidation"
    )

    -- queue the liquidation at this point, because
    -- the user position has been checked, so the liquidation is valid
    -- we don't want anyone to be able to liquidate from this point
    table.insert(LiquidationQueue, target)

    -- TODO: timeout here? (what if this doesn't return in time, the liquidation remains in a pending state)

    -- liquidate the loan
    local loanLiquidationRes = ao.send({
      Target = Tokens[rewardToken],
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = Tokens[msg.From],
      ["X-Action"] = "Liquidate-Borrow",
      ["X-Liquidator"] = liquidator,
      ["X-Target"] = target
    }).receive(Tokens[msg.From])

    -- TODO: check if the liquidation result includes
    -- any refunded tokens. if so, add a handler that
    -- forwards the tokens that were refunded to the
    -- liquidator (on credit notice)

    -- check loan liquidation result
    if loanLiquidationRes.Tags.Error then
      -- remove from queue
      LiquidationQueue = utils.filter(
        function (v) return v ~= target end,
        LiquidationQueue
      )

      return msg.reply({
        Error = "Failed to liquidate loan (" .. loanLiquidationRes.Tags.Error .. ")"
      })
    end

    -- liquidate the position (transfer out the reward)
    local positionLiquidationRes = ao.send({
      Target = Tokens[rewardToken],
      Action = "Liquidate-Position",
      Quantity = "", -- TODO
      Liquidator = liquidator,
      ["Liquidation-Target"] = target
    }).receive()

    -- TODO: if failed reset liquidation

    -- TODO: remove from liquidation queue

    -- send confirmation to the liquidator
    ao.send({
      Target = liquidator,
      Action = "Liquidate-Confirmation",
      ["Liquidation-Target"] = target,
      ["From-Quantity"] = msg.Tags.Quantity,
      ["To-Quantity"] = "" -- TODO
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

-- Get the value of a quantity of the provided assets. The function
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
---@param to { ticker: string, denomination: number } Target token ticker and denomination
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
