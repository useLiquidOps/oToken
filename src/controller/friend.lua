local assertions = require ".utils.assertions"
local utils = require ".utils.utils"
local json = require "json"

local friend = {}

---@alias Friend { id: string; ticker: string; oToken: string; denomination: number; }

---@type HandlerFunction
function friend.add(msg)
  -- validate address
  local newFriend = msg.Tags.Friend
  local friendToken = msg.Tags.Token
  local friendTicker = msg.Tags.Ticker
  local friendDenomination = tonumber(msg.Tags.Denomination)

  assert(
    assertions.isAddress(newFriend),
    "Invalid friend address " .. newFriend
  )
  assert(
    assertions.isAddress(friendToken),
    "Invalid token address " .. friendToken
  )
  assert(
    friendTicker ~= nil,
    "No ticker supplied for friend collateral"
  )
  assert(
    not utils.find(
      ---@param f Friend
      function (f)
        return f.id == friendToken or
          f.oToken == newFriend or
          f.ticker == friendTicker
      end,
      Friends
    ),
    "Friend already added"
  )
  assert(
    newFriend ~= ao.id and friendTicker ~= CollateralTicker and friendToken ~= CollateralID,
    "Cannot add itself as a friend"
  )

  -- add friend
  table.insert(Friends, {
    id = friendToken,
    ticker = friendTicker,
    oToken = newFriend,
    denomination = friendDenomination
  })

  -- notify the sender
  msg.reply({
    Action = "Friend-Added",
    Friend = newFriend
  })
end

---@type HandlerFunction
function friend.remove(msg)
  local target = msg.Tags.Friend

  -- remove and list the removed friends
  ---@type Friend[]
  local removed = {}

  Friends = utils.filter(
    ---@param f Friend
    function (f)
      if f.id == target or f.oToken == target or f.ticker == target then
        table.insert(removed, f)
        return false
      end

      return true
    end,
    Friends
  )

  -- check if any were removed
  assert(#removed > 0, "Friend " .. target .. " not yet added")

  -- notify the sender
  msg.reply({
    Action = "Friend-Removed",
    Removed = target,
    Data = json.encode(removed)
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
