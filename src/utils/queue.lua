local mod = {}

-- Check if a user is queued in the controller. This could be
-- due to an ongoing operation involving the collateral or
-- a cooldown
---@param address string User address
---@return boolean
function mod.isQueued(address)
  -- check queue
  ---@type Message
  local res = ao.send({
    Target = ao.env.Process.Owner,
    Action = "Check-Queue-For",
    User = address
  }).receive(nil, Block + 1)

  return res.Tags["In-Queue"] == "true"
end

-- Add or remove a user from the queue in the controller
---@param address string User address
---@param queued boolean User queue status
---@return boolean
function mod.setQueued(address, queued)
  -- try to update the queue
  ---@type Message
  local res = ao.send({
    Target = ao.env.Process.Owner,
    Action = queued and "Add-To-Queue" or "Remove-From-Queue",
    User = address
  }).receive(nil, Block + 1)

  return res.Tags[queued and "Queued-User" or "Unqueued-User"] == address
end

return mod
