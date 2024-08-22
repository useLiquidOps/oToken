local bint = require ".utils.bint"(1024)
local mod = {}

function mod.init()
  Name = Name or ao.env.Process.Tags.Name
  Ticker = Ticker or ao.env.Process.Tags.Ticker
  Logo = Logo or ao.env.Process.Tags.Logo
  Denomination = Denomination or 12
  Balances = Balances or {}
  TotalSupply = TotalSupply or bint.zero()
end

---@param msg Message
function mod.info(msg)
  ao.send({
    Target = msg.From,
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination)
  })
end

---@param msg Message
function mod.total_supply(msg)
  ao.send({
    Target = msg.From,
    ["Total-Supply"] = tostring(TotalSupply),
    Ticker = Ticker,
    Data = tostring(TotalSupply)
  })
end

return mod
