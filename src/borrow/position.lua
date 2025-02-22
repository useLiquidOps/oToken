local oracle = require ".liquidations.oracle"
local scheduler = require ".utils.scheduler"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = { handlers = {} }

---@alias Position { collateralization: Bint, capacity: Bint, borrowBalance: Bint, liquidationLimit: Bint }

-- Get local position for a user (in units of the collateral)
---@param address string User address
---@return Position
function mod.position(address)
  local zero = bint.zero()

  -- result template
  ---@type Position
  local res = {
    collateralization = zero,
    capacity = zero,
    borrowBalance = zero,
    liquidationLimit = zero
  }

  -- the process holds collateral, let's calculate limits
  -- from the oToken balance (capacity, liquidation limit, etc.)
  if Balances[address] and Balances[address] ~= "0" then
    -- base data for calculations
    local balance = bint(Balances[address])
    local totalPooled = bint(Available) + bint(Lent)

    -- the value of the balance in terms of the underlying asset
    -- (the total collateral for the user, represented by the oToken)
    res.collateralization = bint.udiv(
      totalPooled * balance,
      bint(TotalSupply)
    )

    -- local borrow capacity in units of the underlying asset
    res.capacity = bint.udiv(
      res.collateralization * bint(CollateralFactor),
      bint(100)
    )

    -- liquidation limit in units of the underlying assets
    res.liquidationLimit = bint.udiv(
      res.collateralization * bint(LiquidationThreshold),
      bint(100)
    )
  end

  -- if the user has unpaid depth (an active loan),
  -- that will be the borrow balance
  if Loans[address] and Loans[address] ~= "0" then
    res.borrowBalance = bint(Loans[address])
  end

  -- if the user has unpaid interest, that also needs
  -- to be added to the borrow balance
  if Interests[address] and Interests[address].value ~= "0" then
    res.borrowBalance = res.borrowBalance + bint(Interests[address].value or 0)
  end

  return res
end

-- Get the global position for a user (in USD, using oracle prices)
---@param address string User address
---@return Position
function mod.globalPosition(address)
  local zero = bint.zero()

  -- get local positions from friend processes
  local positions = scheduler.schedule(table.unpack(utils.map(
    function (id) return { Target = id, Action = "Position", Recipient = address } end,
    Friends
  )))

  -- tickers to fetch prices for
  local tickers = utils.map(
    ---@param pos Message
    function (pos) return pos.Tags["Collateral-Ticker"] end,
    positions
  )
  table.insert(tickers, CollateralTicker)

  -- load prices for friend process collaterals + the local collateral
  local rawPrices = oracle.getPrices(tickers)

  -- load local position
  local localPosition = mod.position(address)

  -- result template
  ---@type Position
  local res = {
    collateralization = oracle.getValue(
      rawPrices,
      localPosition.collateralization,
      CollateralTicker,
      CollateralDenomination
    ),
    capacity = oracle.getValue(
      rawPrices,
      localPosition.capacity,
      CollateralTicker,
      CollateralDenomination
    ),
    borrowBalance = oracle.getValue(
      rawPrices,
      localPosition.borrowBalance,
      CollateralTicker,
      CollateralDenomination
    ),
    liquidationLimit = oracle.getValue(
      rawPrices,
      localPosition.liquidationLimit,
      CollateralTicker,
      CollateralDenomination
    ),
  }

  -- calculate global position in USD
  for _, position in ipairs(positions) do
    res.collateralization = res.collateralization + ora
  end
end

-- Local position action handler
---@type HandlerFunction
function mod.handlers.localPosition(msg)
  local account = msg.Tags.Recipient or msg.From
  local position = mod.position(account)

  msg.reply({
    ["Collateral-Ticker"] = CollateralTicker,
    ["Collateral-Denomination"] = tostring(CollateralDenomination),
    Collateralization = tostring(position.collateralization),
    Capacity = tostring(position.capacity),
    ["Borrow-Balance"] = tostring(position.borrowBalance),
    ["Liquidation-Limit"] = tostring(position.liquidationLimit)
  })
end

return mod
