local assertions = require ".utils.assertions"

local mod = {}

---@type HandlerFunction
function mod.setup()
  -- validate wAO address
  local wAOProcess = ao.env.Process.Tags["WAO-Process"]

  if not wAOProcess then return end
  assert(assertions.isAddress(wAOProcess), "Invalid wAO process id")

  WrappedAO = wAOProcess
end

-- Claims and distributes accrued AO yield for owAR
---@type HandlerFunction
function mod.delegate()
  -- only run if defined
  if not WrappedAO then return end

  -- record oToken balances, so the correct quantities are used
  -- after the handler below is triggered later
  local balances = Balances -- TODO: fix this to clone the balances

  -- claim accrued AO, but do not stop execution with .receive()
  --
  -- this is necessary, because this handler runs before interactions
  -- (mint/redeem/liquidate position/transfer) that should not be delayed
end

return mod
