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

return mod
