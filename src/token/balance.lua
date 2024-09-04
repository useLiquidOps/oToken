local json = require "json"

local mod = {}

---@param msg Message
function mod.balance(msg)
  local account = msg.Tags.Recipient or msg.From
  local balance = Balances[account] or "0"

  msg.reply({
    Balance = balance,
    Ticker = Ticker,
    Data = balance
  })
end

---@param msg Message
function mod.balances(msg)
  msg.reply({
    Ticker = Ticker,
    Data = json.encode(Balances)
  })
end

return mod
