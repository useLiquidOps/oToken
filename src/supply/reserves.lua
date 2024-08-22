---@type HandlerFunction
local function reserves(msg)
  ao.send({
    Target = msg.From,
    Action = "Reserves",
    Available = tostring(Available),
    Lent = tostring(Lent)
  })
end

return reserves
