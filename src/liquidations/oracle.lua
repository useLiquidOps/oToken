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

-- Get the price of an asset in terms of another asset
---@param qty Bint Quantity to determinate the value of
---@param from string From token ticker
---@param to string? Price unit token ticker
---@return Bint
function mod.getPrice(qty, from, to)
  ---@type OracleData
  local data = ao.send({
    Target =  Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode({ from, to })
  }).receive().Data

  assert(data[from] ~= nil and data[from].v, "No data returned from the oracle for " .. from)
  assert(
    not to or (data[to] ~= nil and data[to].v ~= nil),
    "No data returned from the oracle for " .. to
  )

  -- denominator to use integers instead of floating point numbers
  local denominator = oracleUtils.getFractionsCount(data[from].v)

  -- usd value
  local usdValDenominated = qty * oracleUtils.getDenominated(data[from].v, denominator)

  -- return USD value if no target asset was provided
  if not to then
    return bint.udiv(
      usdValDenominated,
      bint(10 ^ denominator)
    )
  end

  -- select larger denominator for more precision
  denominator = oracleUtils.getMultiplier(data[from].v, data[to].v)

  --
  -- TODO: figure out how to account for token denominations (maybe warp will store denominated values?)
  --

  -- calculate price based on the usd price relations
  return bint.udiv(
    usdValDenominated,
    oracleUtils.getDenominated(data[to].v, denominator)
  )
end

-- Get multiplier that can be used to create an integer from a float
-- without loosing precision
---@param qtyA number First quantity
---@param qtyB number Second quantity
function oracleUtils.getMultiplier(qtyA, qtyB)
  local qtyAFractions = oracleUtils.getFractionsCount(qtyA)
  local qtyBFractions = oracleUtils.getFractionsCount(qtyB)

  return qtyAFractions > qtyBFractions and qtyAFractions or qtyBFractions
end

-- Get the fractional part's length
---@param val number Full number
function oracleUtils.getFractionsCount(val)
  return string.len(string.match(tostring(val), "%.(.*)"))
end

-- Get a float's biginteger denominated form
---@param val number Floating point value
---@param denominator number Integer denominator
function oracleUtils.getDenominated(val, denominator)
  local denominated = string.gsub(tostring(val), "%.", "")
  local fractions = oracleUtils.getFractionsCount(val)

  if fractions < denominator then
    denominated = denominated .. string.rep("0", denominator - fractions)
  end

  return bint(denominated)
end

return mod
