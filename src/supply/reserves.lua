---@type HandlerFunction
local function reserves(msg)
  msg.reply({
    Action = "Reserves",
    Available = tostring(Available),
    Lent = tostring(Lent)
  })
end

return reserves
