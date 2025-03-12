local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {
  utils = {},
  usdDenomination = 12
}

---@alias OracleInstance { getValue: fun(quantity: Bint, symbol: string): Bint }
---@alias HandlerWithOracle fun(msg: Message, env: Message, oracle: OracleInstance): any
---@alias OracleData table<string, { t: number, a: string, v: number }>
---@alias FetchedPrices table<string, { price: Bint, timestamp: number }>
---@alias RawPrices table<string, { price: number, timestamp: number }>

-- Initializes the oracle configuration from the spawn message
---@type HandlerFunction
function mod.setup()
  -- oracle process id
  Oracle = Oracle or ao.env.Process.Tags.Oracle

  -- oracle delay tolerance in milliseconds
  ---@type number
  MaxOracleDelay = MaxOracleDelay or tonumber(ao.env.Process.Tags["Oracle-Delay-Tolerance"]) or 0

  -- cached price
  -- this should only be used within the same request
  ---@type RawPrices
  PriceCache = PriceCache or {}
end

-- Sync all known friends' collateral price
---@return FetchedPrices
function mod.sync()
  -- collect tickers to fetch the price for
  local tickers = utils.map(
    ---@param friend Friend
    function (friend) return friend.ticker end,
    Friends
  )

  -- add local collateral
  table.insert(tickers, CollateralTicker)

  -- request prices from oracle
  ---@type string|nil
  local rawData = ao.send({
    Target = Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode(tickers)
  }).receive().Data

  -- check if the oracle returned anything in the data field
  assert(type(rawData) == "string" and rawData ~= "", "The oracle did not return any data")

  -- try parsing as json
  ---@type boolean, OracleData
  local parsed, data = pcall(json.decode, rawData)

  assert(parsed, "Could not parse oracle data")

  -- result
  ---@type FetchedPrices
  local res = {}

  -- parse prices
  for ticker, p in pairs(data) do
    res[ticker] = {
      price = mod.utils.getUSDDenominated(p.v),
      timestamp = p.t
    }
  end

  return res
end

-- Calculate a token quantity value in USD
---@param quantity Bint Quantity to get the value for
---@param symbol string Token symbol for the quantity
---@param data FetchedPrices Parsed price data from the oracle
---@return Bint
function mod.calculateValue(quantity, symbol, data)
  -- no calculations needed for 0 quantity
  local zero = bint.zero()
  if quantity == zero then return zero end

  -- price per unit
  local priceData = data[symbol]

  -- check if price is fetched
  assert(priceData ~= nil, symbol .. " price has not been received from the oracle")

  -- check if price is outdated
  assert(
    priceData.timestamp + MaxOracleDelay >= Timestamp,
    symbol .. " price is outdated"
  )

  -- find denomination, error if there is none defined
  local denomination = (utils.find(
    ---@param friend Friend
    function (friend) return friend.ticker == symbol end,
    Friends
  ) or {}).denomination

  -- for the local collateral
  if symbol == CollateralTicker then
    denomination = CollateralDenomination
  end

  assert(denomination ~= nil, "No denomination provided for " .. symbol)

  -- the value of the quantity
  -- (USD price value is denominated for precision,
  -- but the result needs to be divided according
  -- to the underlying asset's denomination,
  -- because the price data is for the non-denominated
  -- unit.
  -- for this reason, the result is divided according
  -- to its denomination)
  return bint.udiv(
    quantity * priceData.price,
    -- optimize performance by repeating "0" instead of a power operation
    bint("1" .. string.rep("0", denomination))
  )
end

-- Hook for handlers that need the oracle price feed
---@param handler HandlerWithOracle Handler to call with oracle data
---@return HandlerFunction
function mod.withOracle(handler)
  return function (msg, env)
    -- sync prices
    local prices = mod.sync()

    -- call the handler
    return handler(
      msg,
      env,
      {
        getValue = function (quantity, symbol)
          return mod.calculateValue(
            quantity,
            symbol,
            prices
          )
        end
      }
    )
  end
end

-- Get the fractional part's length
---@param val number Full number
function mod.utils.getFractionsCount(val)
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
function mod.utils.getUSDDenominated(val)
  local denominator = mod.usdDenomination

  -- remove decimal point
  local denominated = string.gsub(tostring(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = mod.utils.getFractionsCount(val)

  if fractions < denominator then
    denominated = denominated .. string.rep("0", denominator - fractions)
  elseif fractions > denominator then
    -- get the count of the integer part's digits
    local wholeDigits = string.len(denominated) - fractions

    denominated = string.sub(denominated, 1, wholeDigits + denominator)
  end

  return bint(denominated)
end

return mod
