local assertions = require ".utils.assertions"
local utils = require ".utils.utils"
local json = require "json"

local friend = {}

---@type HandlerFunction
function friend.add(msg)
  -- validate address
  local newFriend = msg.Tags.Friend
  local friendTicker = msg.Tags["Friend-Ticker"]

  assert(
    assertions.isAddress(newFriend),
    "Invalid friend address " .. newFriend
  )
  assert(
    friendTicker ~= nil,
    "No ticker supplied for friend collateral"
  )
  assert(
    not Friends[friendTicker] and not utils.includes(newFriend, utils.values(Friends)),
    "Friend already added"
  )
  assert(
    newFriend ~= ao.id and friendTicker ~= CollateralTicker,
    "Cannot add itself as a friend"
  )

  -- add friend
  Friends[friendTicker] = newFriend

  -- notify the sender
  msg.reply({
    Action = "Friend-Added",
    Friend = newFriend,
    ["Friend-Ticker"] = friendTicker
  })
end

---@type HandlerFunction
function friend.remove(msg)
  -- find friend
  local target = msg.Tags.Friend

  -- remove by ticker
  if Friends[target] then
    Friends[target] = nil
  else
    ---@type string|nil
    local friendTicker = nil

    for ticker, oToken in pairs(Friends) do
      if oToken == target then
        friendTicker = ticker
      end
    end

    -- check if the address provided is in the friend list
    assert(friendTicker ~= nil, "Address is not a friend yet")

    Friends[friendTicker] = nil
  end

  -- notify the sender
  msg.reply({
    Action = "Friend-Removed",
    Removed = target
  })
end

---@type HandlerFunction
function friend.list(msg)
  msg.reply({
    Action = "Friend-List",
    Data = next(Friends) ~= nil and json.encode(Friends) or "{}"
  })
end

return friend
