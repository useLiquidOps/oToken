local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {}
local oracleUtils = {}

---@alias OracleData table<string, { t: number, a: string, v: number }>
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias ResultItem { ticker: string, price: Bint }
---@alias CachedPrice { price: number, timestamp: number }
---@alias RawPrices table<string, { price: number, timestamp: number }>

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

---@type HandlerFunction
function mod.timeoutSync(msg)
  -- filter out prices that are no longer up to date
  for ticker, data in pairs(PriceCache) do
    if data.timestamp + MaxOracleDelay < msg.Timestamp then
      PriceCache[ticker] = nil
    end
  end
end

-- Get price data for an array of token symbols
---@param symbols string[] Token symbols
function mod.getPrices(symbols)
  ---@type RawPrices
  local res = {}

  -- nothing to sync
  if #symbols == 0 then return res end

  -- request prices from oracle
  ---@type string|nil
  local rawData = ao.send({
    Target = Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode(symbols)
  }).receive().Data

  -- no price data returned
  if not rawData or rawData == "" then
    return res
  end

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
function mod.getValue(rawPrices, quantity, ticker, denomination)
  local res = mod.getValues(rawPrices, {
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
function mod.getValues(rawPrices, quantities)
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
        v.quantity * oracleUtils.getUSDDenominated(rawPrices[v.ticker].price),
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

-- Get the price/value of a quantity of the provided assets. The function
-- will only provide up to date values, outdated and nil values will be
-- filtered out
---@param ... PriceParam
---@return ResultItem[]
function mod.getPrice(...)
  local args = {...}
  local zero = bint.zero()

  -- prices that require to be synced
  ---@type string[]
  local pricesToSync = utils.map(
    ---@param v PriceParam
    function (v) return v.ticker end,
    utils.filter(
      ---@param v PriceParam
      function (v) return not PriceCache[v.ticker] and not bint.eq(v.quantity, zero) end,
      args
    )
  )

  -- if the cache is disabled or there is no price
  -- data cached, fetch the price
  if #pricesToSync > 0 then
    ---@type string|nil
    local rawData = ao.send({
      Target = Oracle,
      Action = "v2.Request-Latest-Data",
      Tickers = json.encode(pricesToSync)
    }).receive(nil, Block + 1).Data

    -- check if there was any data returned
    assert(rawData ~= nil and rawData ~= "", "No data returned from the oracle")

    ---@type OracleData
    local data = json.decode(rawData)

    for ticker, p in pairs(data) do
      -- only add data if the timestamp is up to date
      if p.t <= Timestamp + MaxOracleDelay and p.t >= Timestamp - MaxOracleDelay then
        PriceCache[ticker] = {
          price = p.v,
          timestamp = p.t
        }
      end
    end
  end

  ---@type ResultItem[]
  local results = {}

  local one = bint.one()
  for _, v in ipairs(args) do
    if not v.quantity then v.quantity = one end
    if not bint.eq(v.quantity, zero) then
      -- get cached value
      local cached = PriceCache[v.ticker]

      -- make sure the cached value exists
      assert(cached ~= nil, "No price returned from the oracle for " .. v.ticker)

      -- the value of the quantity
      -- (USD price value is denominated for precision,
      -- but the result needs to be divided according
      -- to the underlying asset's denomination,
      -- because the price data is for the non-denominated
      -- unit)
      local price = bint.udiv(
        v.quantity * oracleUtils.getUSDDenominated(cached.price),
        -- optimize performance by repeating "0" instead of a power operation
        bint("1" .. string.rep("0", v.denomination))
      )

      -- add data
      table.insert(results, {
        ticker = v.ticker,
        price = price
      })
    else
      table.insert(results, {
        ticker = v.ticker,
        price = zero
      })
    end
  end

  return results
end

-- Get the precision used for USD biginteger values
function mod.getUSDDenomination() return 12 end

-- Get the fractional part's length
---@param val number Full number
function oracleUtils.getFractionsCount(val)
  -- check if there is a fractional part 
  -- by trying to find it with a pattern
  local fractionalPart = string.match(tostring(val), "%.(.*)")

  if not fractionalPart then return 0 end

  -- get the length of the fractional part
  return string.len(fractionalPart)
end

-- Get a USD value in a 12 denominated form
---@param val number USD value as a floating point number
function oracleUtils.getUSDDenominated(val)
  local denominator = mod.getUSDDenomination()

  -- remove decimal point
  local denominated = string.gsub(tostring(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = oracleUtils.getFractionsCount(val)

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
