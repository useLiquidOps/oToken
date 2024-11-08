local assertions = {}

Handlers.add(
  "liquidate",
  { Action = "Credit-Notice", ["X-Action"] = "Liquidate" },
  function (msg)
    -- liquidation target
    local target = msg.Tags["X-Target"]

    assert(
      assertions.isAddress(target),
      "Invalid liquidation target"
    )

    -- token to be liquidated 
    -- (the token that is paying for the loan = transferred token)
    local liquidatedToken = msg.From

    -- TODO: check if token is listed

    -- the token of the position that will be liquidated
    -- (this will be sent to the liquidator as a reward)
    local positionToken = msg.Tags["X-Position-Token"]

    -- TODO: check if token is listed

    -- TODO: check user position

    -- TODO: check queue

    -- TODO: queue the liquidation at this point, because
    -- the user position has been checked, so the liquidation is valid
    -- we don't want anyone to be able to liquidate from this point

    -- TODO: step 1: liquidate the loan

    -- TODO: check loan liquidation result
    -- TODO: timeout here? (what if this doesn't return in time, the liquidation remains in a pending state)

    -- TODO: step 2: liquidate the position (transfer out the reward)

    -- TODO: send confirmation to the liquidator
  end
)

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function assertions.isAddress(addr)
  if not type(addr) == "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "[A-z0-9_-]+") == nil then return false end

  return true
end
