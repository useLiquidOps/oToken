local bint = require ".utils.bint"(1024)

local mod = {}

---@alias LocalPosition { collateralization: Bint, capacity: Bint, borrowBalance: Bint, liquidationLimit: Bint }

-- Get local position for a user
---@param address string User address
---@return LocalPosition
function mod.position(address)
  local zero = bint.zero()

  -- result template
  ---@type LocalPosition
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

return mod
