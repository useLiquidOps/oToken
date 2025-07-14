local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)
local utils = require ".utils.utils"

local mod = {}

---@type HandlerFunction
function mod.setup()
  -- validate wAO address
  local wAOProcess = ao.env.Process.Tags["Wrapped-AO-Token"]

  if not wAOProcess then return end
  assert(assertions.isAddress(wAOProcess), "Invalid wAO process id")

  -- wrapped arweave process id
  WrappedAOToken = WrappedAOToken or wAOProcess

  -- remaining quantity to distribute
  RemainingDelegateQuantity = RemainingDelegateQuantity or "0"
end

-- Claims and distributes accrued AO yield for owAR
---@type HandlerFunction
function mod.delegate(msg)
  -- only run if defined
  if not WrappedAOToken then return end

  -- the original message this message was pushed for
  local pushedFor = msg.Tags["Pushed-For"] or msg.Id

  -- record oToken balances before the current interaction, so the
  -- correct quantities are used after the handler below is triggered
  local balancesRecord = {}

  for addr, balance in pairs(Balances) do
    balancesRecord[addr] = balance
  end

  -- claim accrued AO, but do not stop execution with .receive()
  --
  -- this is necessary, because this handler runs before interactions
  -- (mint/redeem/liquidate position/transfer) that should not be delayed
  local claimMsg = ao.send({
    Target = WrappedAOToken,
    Action = "Claim"
  })
  local claimRef = (utils.find(
    function (tag) return tag.name == "Reference" end,
    claimMsg.Tags
  ) or {}).value

  -- add handler that handles a potential claim error/credit-notice
  Handlers.once(
    function (msg)
      local action = msg.Tags.Action

      -- claim error
      if action == "Claim-Error" and msg.From == WrappedAOToken and msg.Tags["X-Reference"] == claimRef then
        return true
      end

      -- credit notice for the claimed AO
      if action == "Credit-Notice" and msg.From == AOToken and msg.Tags["Pushed-For"] == pushedFor then
        return true
      end

      return false
    end,
    function (msg)
      -- do not distribute if there was an error
      if msg.Tags.Action == "Claim-Error" then return end

      -- validate quantity
      assert(
        assertions.isTokenQuantity(msg.Tags.Quantity),
        "Invalid claimed quantity"
      )

      -- quantity to distribute (the incoming + the remainder)
      local quantity = bint(msg.Tags.Quantity) + bint(RemainingDelegateQuantity or "0")

      -- distribute claimed AO
      local remaining = bint(quantity)
      local totalSupply = bint(TotalSupply)
      local zero = bint.zero()

      for addr, rawBalance in pairs(balancesRecord) do
        -- parsed wallet balance
        local balance = bint(rawBalance)

        -- amount to distribute to this wallet
        local distributeQty = quantity.udiv(
          balance * quantity,
          totalSupply
        )

        -- distribute if more than 0
        if bint.ult(zero, distributeQty) then
          ao.send({
            Target = AOToken,
            Action = "Transfer",
            Quantity = tostring(distributeQty),
            Recipient = addr
          })
          remaining = remaining - distributeQty
        end
      end

      -- make sure that the remainder is at least zero, otherwise
      -- something went wrong with the calculations (this should not
      -- happen)
      assert(bint.ule(zero, remaining), "The distribution remainder cannot be less than zero")

      -- update the remaining amount
      RemainingDelegateQuantity = tostring(remaining)
    end
  )
end

return mod
