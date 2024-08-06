local bint = require ".utils.bint"(1024)
local json = require "json"

local mod = {}

---@param msg Message
function mod.balance(msg)
  local account = msg.Tags.Target or msg.From
  local balance = tostring(Balances[account] or bint.zero())

  ao.send({
    Target = msg.From,
    Balance = balance,
    Ticker = Ticker,
    Data = balance
  })
end

---@param msg Message
function mod.balances(msg)
  ---@type table<string, string>
  local raw_balances = {}

  for addr, bal in pairs(Balances) do
    raw_balances[addr] = tostring(bal)
  end

  ao.send({
    Target = msg.From,
    Ticker = Ticker,
    Data = json.encode(raw_balances)
  })
end

return mod
