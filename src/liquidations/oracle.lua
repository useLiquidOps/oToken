local json = require "json"

local mod = {}

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

  -- return USD value if no target asset was provided
  if not to then
    -- TODO bint transformation
  end

  -- TODO: calculate price based on the usd price relations
end

return mod
