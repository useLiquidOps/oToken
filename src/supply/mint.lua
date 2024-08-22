local assertions = require ".utils.assertions"
local bint = require ".utils.bint"(1024)

---@type HandlerFunction
local function mint(msg)
  assert(
    assertions.isTokenQuantity(msg.Tags.Quantity),
    "Invalid transfer quantity"
  )

  -- quantity of tokens supplied
  local quantity = bint(msg.Tags.Quantity)

  -- transfer sender
  local sender = msg.Tags.Sender

  -- amount of loTokens to be minted
  local mintQty = quantity

  -- total tokens pooled
  local totalPooled = Available + Lent

  if not bint.eq(totalPooled, bint.zero()) then
    -- mint in proportion to the already supplied tokens
    mintQty = bint.udiv(
      TotalSupply * quantity,
      totalPooled
    )
  end

  -- update stored quantities (balance, available, total supply)
  Balances[sender] = (Balances[sender] or bint.zero()) + mintQty
  Available = (Available or bint.zero()) + mintQty
  TotalSupply = (TotalSupply or bint.zero()) + mintQty

  ao.send({
    Target = sender,
    Action = "Mint-Confirmation",
    ["Mint-Quantity"] = tostring(mintQty),
    ["Supplied-Quantity"] = msg.Tags.Quantity
  })
end

return mint
