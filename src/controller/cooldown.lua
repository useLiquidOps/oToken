local mod = {}

-- Initializes the cooldown map
---@type HandlerFunction
function mod.setup()
  -- Users - cooldown deadlines in block height
  ---@type table<string, number>
  Cooldowns = Cooldowns or {}

  -- Cooldown period in blocks
  CooldownPeriod = CooldownPeriod or tonumber(ao.env.Process.Tags["Cooldown-Period"]) or 0
end

-- Cooldown middleware/gate that rejects 
-- interactions if the user is on cooldown
---@type HandlerFunction
function mod.gate()

end

return mod
