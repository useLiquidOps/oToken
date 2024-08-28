---@type HandlerFunction
local function reserves(msg)
  msg.reply({
    Action = "Reserves",
    Available = Available,
    Lent = Lent
  })
end

return reserves
