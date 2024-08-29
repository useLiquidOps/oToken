local mod = {}

---@type HandlerFunction
function mod.setup()
  -- token that can be lent/borrowed
  Token = Token or ao.env.Process.Tags.Token

  -- collateralization ratio
  CollateralRatio = CollateralRatio or tonumber(ao.env.Process.Tags.CollateralRatio)

  -- available tokens to be lent
  Available = Available or "0"

  -- tokens borrowed by borrowers
  Lent = Lent or "0"

  -- all loans (values are Bint in string format)
  ---@type table<string, string>
  Loans = Loans or {}

  -- all interests accrued (values are Bint in string format)
  ---@type table<string, string>
  Interests = Interests or {}
end

return mod
