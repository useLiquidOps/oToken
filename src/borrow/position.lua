local mod = {}

---@type HandlerFunction
function mod.capacity()

end

---@type HandlerFunction
function mod.balance(msg)
  local account = msg.Tags.Target or msg.From

  msg.reply({
    Action = "Borrow-Balance-Response",
    ["Borrowed-Quantity"] = Loans[account],
    ["Interest-Quantity"] = Interests[account]
  })
end

return mod
