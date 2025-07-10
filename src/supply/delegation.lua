local assertions = require ".utils.assertions"
local utils = require ".utils.utils"

local mod = {
  aoToken = "0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc"
}

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
function mod.delegate(msg)
  -- only run if defined
  if not WrappedAO then return end

  -- record oToken balances, so the correct quantities are used
  -- after the handler below is triggered later
  local balances = Balances -- TODO: fix this to clone the balances

  -- claim accrued AO, but do not stop execution with .receive()
  --
  -- this is necessary, because this handler runs before interactions
  -- (mint/redeem/liquidate position/transfer) that should not be delayed
  local claimMsg = ao.send({
    Target = WrappedAO,
    Action = "Claim"
  })
  local claimRef = utils.find(
    function (tag) return tag.name == "Reference" end,
    claimMsg.Tags
  )

  -- add handler that handles a potential claim error/credit-notice
  Handlers.once(
    function (msg)
      local action = msg.Tags.Action

      -- claim error
      if action == "Claim-Error" and msg.From == WrappedAO and msg.Tags["X-Reference"] == claimRef then
        return true
      end

      if action == "Credit-Notice" and msg.From ==
    function ()

    end
  )

  -- TODO: save remainder AO with extra (internal) precision and redistribute it later
end

return mod
