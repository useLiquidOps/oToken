local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"
local json = require "json"

---@alias OracleData table<string, { t: number, a: string, v: number }>
---@alias FetchedPrices table<string, { price: Bint, timestamp: number }>

---@class Oracle
local Oracle = {
  ---@type string[]
  symbols = {},
  ---@type table<string, number>
  denominations = {},
  ---@type FetchedPrices
  prices = {},
  -- denomination for usd precision
  usdDenomination = 12,
  utils = {}
}

-- Creates a new Oracle instance and pre-fetches 
-- the price for the given symbols
---@param data table<string, number> Symbol - denomination pairs
---@return Oracle
function Oracle:new(data)
  local instance = {}
  setmetatable(instance, self)
  self.__index = self

  -- construct
  self.symbols = utils.keys(data)
  self.denominations = data

  -- pre-fetch prices
  self:sync()

  return instance
end

-- Initializes the oracle configuration from the spawn message
---@type HandlerFunction
function Oracle.setup()
  -- oracle process id
  OracleID = OracleID or ao.env.Process.Tags.Oracle

  -- oracle delay tolerance in milliseconds
  ---@type number
  MaxOracleDelay = MaxOracleDelay or tonumber(ao.env.Process.Tags["Oracle-Delay-Tolerance"]) or 0
end

-- Sync oracle prices
function Oracle:sync()
  -- don't sync if no symbols are given
  if #self.symbols < 1 then return end

  -- request prices from oracle
  ---@type string|nil
  local rawData = ao.send({
    Target = OracleID,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode(self.symbols)
  }).receive().Data

  -- try parsing as json
  ---@type boolean, OracleData
  local parsed, data = pcall(json.decode, rawData)

  -- could not parse price data, don't sync
  if not parsed then return end

  -- sync price data
  for ticker, p in pairs(data) do
    self.prices[ticker] = {
      price = Oracle.utils.getUSDDenominated(p.v),
      timestamp = p.t
    }
  end
end

-- Get value in USD for a token quantity
---@param quantity Bint Quantity to get the value for
---@param symbol string Token symbol for the quantity
---@return Bint
function Oracle:getValue(quantity, symbol)
  -- no calculations needed for 0 quantity
  local zero = bint.zero()
  if quantity == zero then return zero end

  -- price per unit
  local price = self.prices[symbol]

  -- check if price is fetched
  assert(price ~= nil, symbol .. " price has not been received from the oracle")

  -- check if price is outdated
  assert(
    price.timestamp + MaxOracleDelay >= Timestamp,
    symbol .. " price is outdated"
  )

  -- check if denomination is present
  local denomination = self.denominations[symbol]

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
    quantity * price,
    -- optimize performance by repeating "0" instead of a power operation
    bint("1" .. string.rep("0", denomination))
  )
end

-- Scope an Oracle instance to a token
---@param symbol string Token symbol/ticker
function Oracle:token(symbol)
  return {
    -- Get value in USD for a token quantity
    ---@param quantity Bint Quantity to get the value for
    getValue = function (quantity)
      return self:getValue(quantity, symbol)
    end
  }
end

-- Get the fractional part's length
---@param val number Full number
function Oracle.utils.getFractionsCount(val)
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
function Oracle.utils.getUSDDenominated(val)
  local denominator = Oracle.usdDenomination

  -- remove decimal point
  local denominated = string.gsub(tostring(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = Oracle.utils.getFractionsCount(val)

  if fractions < denominator then
    denominated = denominated .. string.rep("0", denominator - fractions)
  elseif fractions > denominator then
    -- get the count of the integer part's digits
    local wholeDigits = string.len(denominated) - fractions

    denominated = string.sub(denominated, 1, wholeDigits + denominator)
  end

  return bint(denominated)
end

return Oracle
