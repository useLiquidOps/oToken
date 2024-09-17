local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

local mod = {}
local oracleUtils = {}

---@alias OracleData table<string, { t: number, a: string, v: number }>
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias ResultItem { ticker: string, price: Bint?, timestamp: number }
---@alias CachedPrice { price: number, timestamp: number }

---@type HandlerFunction
function mod.setup()
  -- oracle process id
  Oracle = Oracle or ao.env.Process.Tags.Oracle

  -- oracle delay tolerance in miliseconds
  MaxOracleDelay = MaxOracleDelay or ao.env.Process.Tags["Oracle-Delay-Tolerance"]

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

-- Get the price/value of a quantity of the underlying asset
---@param ... PriceParam
---@return Bint[]
function mod.getPrice(...)
  local args = {...}
  local one = bint.one()
  local zero = bint.zero()

  -- quantity should be 1 by default
  for k, v in ipairs(args) do
    if not v.quantity then
      args[k].quantity = one
    end
  end

  -- prices that require to be synced

  -- if the cache is disabled or there is no price
  -- data cached, fetch the price
  if not price then
    ---@type OracleData
    local data = ao.send({
      Target =  Oracle,
      Action = "v2.Request-Latest-Data",
      Tickers = json.encode(utils.map(
        ---@param v PriceParam
        function (v) return v.ticker end,
        utils.filter(
          ---@param v PriceParam
          function (v) return not bint.eq(v.quantity, zero) end,
          args
        )
      ))
    }).receive().Data

    for ticker, p in pairs(data) do
      prices[ticker] = {
        price = p.v,
        timestamp = p.t
      }
    end
  end

  ---@type ResultItem[]
  local results = {}

  -- TODO: validate timestamps
  -- this is probably only needed for tokens that have non-0 quantity,
  -- and are required for collateralization
  -- we also need to figure out the period that is acceptable for the timestamp

  -- the value of the quantity
  -- (USD price value is denominated for precision,
  -- but the result needs to be divided according
  -- to the underlying asset's denomination,
  -- because the price data is for the non-denominated
  -- unit)
  local value = bint.udiv(
    quantity * oracleUtils.getUSDDenominated(price),
    -- optimize performance by repeating "0" instead of a power operation
    bint("1" .. string.rep("0", WrappedDenomination))
  )

  return value
end

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
  local denominator = 12

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
