local bint = require ".utils.bint"(1024)

local mod = {}

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function mod.isAddress(addr)
  if not type(addr) == "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "[A-z0-9_-]+") == nil then return false end

  return true
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
      if type(val) == "number" and (val ~= val or val % 1 ~= 0) then
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
  if type(qty) == "nil" then return false end
  if not mod.isBintRaw(qty) then return false end
  if type(qty) == "number" and qty < 0 then return false end
  if type(qty) == "string" and string.sub(qty, 1, 1) == "-" then
    return false
  end

  return true
end

return mod
