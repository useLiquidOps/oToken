local bint = require ".utils.bint"(1024)

local mod = {}

function mod.init()
  -- available tokens to be lent
  Available = Available or bint.zero()

  -- tokens borrowed by borrowers
  Lent = Lent or bint.zero()

  -- all loans
  ---@type table<string, Bint>
  Loans = Loans or {}

  -- all interests accrued
  ---@type table<string, Bint>
  Interests = Interests or {}
end

return mod
