local assertions = require ".utils.assertions"
local utils = require ".utils.utils"
local json = require "json"

local friend = {}

---@type HandlerFunction
function friend.add(msg)
  -- validate address
  local newFriend = msg.Tags.Friend

  assert(
    assertions.isAddress(newFriend),
    "Invalid friend address " .. newFriend
  )

  -- add friend
  table.insert(Friends, newFriend)

  -- notify the sender
  msg.reply({
    Action = "Friend-Added",
    Friend = newFriend
  })
end

---@type HandlerFunction
function friend.remove(msg)
  -- find friend
  local target = msg.Tags.Friend
  local _, friendIndex = utils.find(
    function (v) return v == target end,
    Friends
  )

  -- check if the address provided is in the friend list
  assert(friendIndex ~= nil, "Address is not a friend yet")

  -- remove friend
  table.remove(Friends, friendIndex)

  -- notify the sender
  msg.reply({
    Action = "Friend-Removed",
    Friend = target
  })
end

---@type HandlerFunction
function friend.list(msg)
  msg.reply({
    Action = "Friend-List",
    Data = json.encode(Friends)
  })
end

return friend
