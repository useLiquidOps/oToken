local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function mod.isAddress(addr)
  if type(addr) ~= "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "^[A-z0-9_-]+$") == nil then return false end

  return true
end

-- Checks if an input is not inf or nan
---@param val number Input to check
function mod.isValidNumber(val)
  return type(val) == "number" and
    val == val and
    val ~= math.huge and
    val ~= -math.huge
end

-- Checks if an input is not inf or nan and is an integer
---@param val number Input to check
function mod.isValidInteger(val)
  return mod.isValidNumber(val) and val % 1 == 0
end

-- Validates if the provided value can be parsed as a Bint
---@param val any Value to validate
---@return boolean
function mod.isBintRaw(val)
  local success, result = pcall(
    function ()
      -- check if the value is convertible to a Bint
      if type(val) ~= "number" and type(val) ~= "string" and not bint.isbint(val) then
        return false
      end

      -- check if the val is an integer and not infinity, in case if the type is number
      if (type(val) == "number" or type(val) == "string") and not mod.isValidInteger(tonumber(val)) then
        return false
      end

      return true
    end
  )

  return success and result
end

-- Verify if the provided value can be converted to a valid token quantity
---@param qty any Raw quantity to verify
---@return boolean
function mod.isTokenQuantity(qty)
  local numVal = tonumber(qty)
  if not numVal or numVal <= 0 then return false end
  if not mod.isBintRaw(qty) then return false end
  if type(qty) == "number" and qty < 0 then return false end
  if type(qty) == "string" and string.sub(qty, 1, 1) == "-" then
    return false
  end

  return true
end

-- Verify that user user will have enough collateralization after
-- the specified quantity is added to their debt
---@param addedDebt Bint Added dept/ borrow quantity in USD
---@param position Position Current user position in USD
---@return boolean
function mod.isCollateralizedWith(addedDebt, position)
  -- first we check if the borrow balance is less than the capacity
  --
  -- this is important and required, because in the second part of the assertion,
  -- we subtract the borrow balance from the capacity, but we're dealing
  -- with unsigned integers
  -- without this, the second part of the assertion could be an invalid
  -- number, if the borrow balance is higher than the capacity
  return bint.ult(position.borrowBalance, position.capacity) and
    bint.ule(addedDebt, position.capacity - position.borrowBalance)
end

-- Verify that the user will have enough collateralization after
-- the specified quantity is removed from their collateral
---@param removedCapacity Bint Removed capacity quantity in USD (adjusted collateral quantity)
---@param position Position Current user position in USD
---@return boolean
function mod.isCollateralizedWithout(removedCapacity, position)
  return bint.ule(removedCapacity, position.capacity) and
    bint.ule(position.borrowBalance, position.capacity - removedCapacity)
end

-- Verify that provided value is a valid integer percentage (between 0 and 100)
---@param val unknown Value to test
---@return boolean
function mod.isPercentage(val)
  if not val or type(val) ~= "number" then return false end
  return val // 1 == val and val >= 0 and val <= 100
end

-- Check if a process is a "friend" process
-- (part of the protocol as an oToken)
---@param process string Address of the process
---@return boolean
function mod.isFriend(process)
  return utils.find(
    ---@param friend Friend
    function (friend)
      return friend.oToken == process
    end,
    Friends
  ) ~= nil
end

return mod
