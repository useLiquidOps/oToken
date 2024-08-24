local json = require "json"

local mod = {}
local oracleUtils = {}

---@alias OracleData table<string, { t: number, a: string, v: number }>

function mod.init()
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

  -- return USD value if no target asset was provided
  if not to then
    -- TODO bint transformation
  end

  --denominator = 10 ^ orac
  -- select larger denominator for more precision
  denominator = oracleUtils.getMultiplier(data[from].v, data[to].v)

  -- TODO: calculate price based on the usd price relations
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

return mod
