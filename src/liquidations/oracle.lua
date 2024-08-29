local bint = require ".utils.bint"(1024)
local json = require "json"

local mod = {}
local oracleUtils = {}

---@alias OracleData table<string, { t: number, a: string, v: number }>

---@type HandlerFunction
function mod.setup()
  -- oracle process id
  Oracle = Oracle or ao.env.Process.Tags.Oracle
end

-- Get the price/value of a quantity of the underlying asset
---@param quantity Bint? Quantity to determinate the value of
---@return Bint
function mod.getUnderlyingPrice(quantity)
  -- quantity should be 1 by default
  if not quantity then quantity = bint.one() end

  ---@type OracleData
  local data = ao.send({
    Target =  Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode({ Token })
  }).receive().Data

  assert(
    data[Token] ~= nil and data[Token].v,
    "No data returned from the oracle for the underlying token (" .. Token .. ")"
  )

  -- the value of the quantity
  -- (USD price value is denominated for precision,
  -- but the result needs to be divided according
  -- to the underlying asset's denomination,
  -- because the price data is for the non-denominated
  -- unit)
  local value = bint.udiv(
    quantity * oracleUtils.getUSDDenominated(data[Token].v),
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
