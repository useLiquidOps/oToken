local bint = require ".utils.bint"(1024)
local mod = {}

function mod.init(_, env)
  Name = Name or env.Process.Tags.Name
  Ticker = Ticker or env.Process.Tags.Ticker
  Logo = Logo or env.Process.Tags.Logo
  Denomination = Denomination or 12
  Balances = Balances or {}
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
  local total_supply = bint.zero()

  for _, balance in pairs(Balances) do
    total_supply = total_supply + balance
  end

  ao.send({
    Target = msg.From,
    ["Total-Supply"] = tostring(total_supply),
    Ticker = Ticker,
    Data = tostring(total_supply)
  })
end

return mod
