local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {}
local oracleUtils = {}

---@alias OracleData table<string, { t: number, a: string, v: number }>
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias ResultItem { ticker: string, price: Bint }
---@alias CachedPrice { price: number, timestamp: number }

---@type HandlerFunction
function mod.setup()
  -- oracle process id
  Oracle = Oracle or ao.env.Process.Tags.Oracle

  -- oracle delay tolerance in miliseconds
  ---@type number
  MaxOracleDelay = MaxOracleDelay or tonumber(ao.env.Process.Tags["Oracle-Delay-Tolerance"]) or 0

  -- cached price
  -- this should only be used within the same request
  ---@type table<string, { price: number, timestamp: number }>
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

-- Get the price/value of a quantity of the provided assets. The function
-- will only provide up to date values, outdated and nil values will be
-- filtered out
---@param timestamp number Current message timestamp
---@param cache boolean Force use cache
---@param ... PriceParam
---@return ResultItem[]
function mod.getPrice(timestamp, cache, ...)
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
  if #pricesToSync > 0 and not cache then
    ---@type string|nil
    local rawData = ao.send({
      Target =  Oracle,
      Action = "v2.Request-Latest-Data",
      Tickers = json.encode(pricesToSync)
    }).receive().Data

    -- check if there was any data returned
    assert(rawData ~= nil and rawData ~= "", "No data returned from the oracle")

    ---@type OracleData
    local data = json.decode(rawData)

    for ticker, p in pairs(data) do
      -- only add data if the timestamp is up to date
      if p.t + MaxOracleDelay >= timestamp then
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
