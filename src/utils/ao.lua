-- Copyright (c) 2024 Forward Research
-- Code from the aos codebase: https://github.com/permaweb/aos

local oldao = ao or {}
local ao = {
  _version = "0.0.6",
  id = oldao.id or "",
  _module = oldao._module or "",
  authorities = oldao.authorities or {},
  reference = oldao.reference or 0,
  outbox = oldao.outbox or {Output = {}, Messages = {}, Spawns = {}, Assignments = {}},
  nonExtractableTags = {
    'Data-Protocol', 'Variant', 'From-Process', 'From-Module', 'Type',
    'From', 'Owner', 'Anchor', 'Target', 'Data', 'Tags'
  },
  nonForwardableTags = {
    'Data-Protocol', 'Variant', 'From-Process', 'From-Module', 'Type',
    'From', 'Owner', 'Anchor', 'Target', 'Tags', 'TagArray', 'Hash-Chain',
    'Timestamp', 'Nonce', 'Epoch', 'Signature', 'Forwarded-By',
    'Pushed-For', 'Read-Only', 'Cron', 'Block-Height', 'Reference', 'Id',
    'Reply-To'
  }
}

local function _includes(list)
  return function(key)
    local exists = false
    for _, listKey in ipairs(list) do
      if key == listKey then
        exists = true
        break
      end
    end
    if not exists then return false end
    return true
  end
end

local function isArray(table)
  if type(table) == "table" then
    local maxIndex = 0
    for k, v in pairs(table) do
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        return false -- If there's a non-integer key, it's not an array
      end
      maxIndex = math.max(maxIndex, k)
    end
    -- If the highest numeric index is equal to the number of elements, it's an array
    return maxIndex == #table
  end
  return false
end

local function padZero32(num) return string.format("%032d", num) end

function ao.clone(obj, seen)
  -- Handle non-tables and previously-seen tables.
  if type(obj) ~= 'table' then return obj end
  if seen and seen[obj] then return seen[obj] end

  -- New table; mark it as seen and copy recursively.
  local s = seen or {}
  local res = {}
  s[obj] = res
  for k, v in pairs(obj) do res[ao.clone(k, s)] = ao.clone(v, s) end
  return setmetatable(res, getmetatable(obj))
end

function ao.normalize(msg)
  for _, o in ipairs(msg.Tags) do
    if not _includes(ao.nonExtractableTags)(o.name) then
      msg[o.name] = o.value
    end
  end
  return msg
end

function ao.sanitize(msg)
  local newMsg = ao.clone(msg)

  for k, _ in pairs(newMsg) do
    if _includes(ao.nonForwardableTags)(k) then newMsg[k] = nil end
  end

  return newMsg
end

function ao.init(msg, env)
  if ao.id == "" or ao.id == nil then ao.id = env.Process.Id end

  if ao._module == "" then
    for _, o in ipairs(env.Process.Tags) do
      if o.name == "Module" then ao._module = o.value end
    end
  end

  if #ao.authorities < 1 then
    for _, o in ipairs(env.Process.Tags) do
      if o.name == "Authority" then
        table.insert(ao.authorities, o.value)
      end
    end
  end

  ao.outbox = {Output = {}, Messages = {}, Spawns = {}, Assignments = {}}
  ao.env = env
  ao.msg = msg

  ao.normalize(msg)

  msg.TagArray = msg.Tags
  msg.Tags = ao.normalize_tags(msg)

  ao.env.Process.TagArray = ao.env.Process.Tags
  ao.env.Process.Tags = ao.normalize_tags(ao.env.Process)

  ao.env.Process.Owner = ao.env.Process.Tags["From-Process"] or ao.env.Process.Owner

  ao.clearOutbox()

  if type(msg.Timestamp) == "string" then msg.Timestamp = tonumber(msg.Timestamp) end

  return (msg.From == msg.Owner or ao.isTrusted(msg)) and
    (not ao.isAssignment(msg) or ao.isAssignable(msg))
end

function ao.log(txt)
  if type(ao.outbox.Output) == 'string' then
    ao.outbox.Output = {ao.outbox.Output}
  end
  table.insert(ao.outbox.Output, txt)
end

-- clears outbox
function ao.clearOutbox()
  ao.outbox = {Output = {}, Messages = {}, Spawns = {}, Assignments = {}}
end

function ao.send(msg)
  assert(type(msg) == 'table', 'msg should be a table')
  ao.reference = ao.reference + 1
  local referenceString = tostring(ao.reference)

  local message = {
    Target = msg.Target,
    Data = msg.Data,
    Anchor = padZero32(ao.reference),
    Tags = {
      {name = "Data-Protocol", value = "ao"},
      {name = "Variant", value = "ao.TN.1"},
      {name = "Type", value = "Message"},
      {name = "Reference", value = referenceString}
    }
  }

  -- if custom tags in root move them to tags
  for k, v in pairs(msg) do
    if not _includes({"Target", "Data", "Anchor", "Tags", "From"})(k) then
      table.insert(message.Tags, {name = k, value = v})
    end
  end

  if msg.Tags then
    if isArray(msg.Tags) then
      for _, o in ipairs(msg.Tags) do
        table.insert(message.Tags, o)
      end
    else
      for k, v in pairs(msg.Tags) do
        table.insert(message.Tags, {name = k, value = v})
      end
    end
  end

  -- If running in an environment without the AOS Handlers module, do not add
  -- the onReply and receive functions to the message.
  if not Handlers then return message end

  -- clone message info and add to outbox
  local extMessage = {}
  for k, v in pairs(message) do extMessage[k] = v end

  -- add message to outbox
  table.insert(ao.outbox.Messages, extMessage)

  -- add callback for onReply handler(s)
  message.onReply =
    function(...) -- Takes either (AddressThatWillReply, handler(s)) or (handler(s))
      local from, resolver
      if select("#", ...) == 2 then
        from = select(1, ...)
        resolver = select(2, ...)
      else
        from = message.Target
        resolver = select(1, ...)
      end

      -- Add a one-time callback that runs the user's (matching) resolver on reply
      Handlers.once({From = from, ["X-Reference"] = referenceString},
              resolver)
    end

  message.receive = function(from, timeout)
    if from == nil then from = message.Target end

    return Handlers.receive({
      From = from,
      ["X-Reference"] = referenceString
    }, timeout)
  end

  return message
end

function ao.spawn(module, msg)
  assert(type(module) == "string", "Module source id is required!")
  assert(type(msg) == 'table', 'Message must be a table')
  -- inc spawn reference
  ao.reference = ao.reference + 1
  local spawnRef = tostring(ao.reference)

  local spawn = {
    Data = msg.Data or "NODATA",
    Anchor = padZero32(ao.reference),
    Tags = {
      {name = "Data-Protocol", value = "ao"},
      {name = "Variant", value = "ao.TN.1"},
      {name = "Type", value = "Process"},
      {name = "From-Process", value = ao.id},
      {name = "From-Module", value = ao._module},
      {name = "Module", value = module},
      {name = "Reference", value = spawnRef}
    }
  }

  -- if custom tags in root move them to tags
  for k, v in pairs(msg) do
    if not _includes({"Target", "Data", "Anchor", "Tags", "From"})(k) then
      table.insert(spawn.Tags, {name = k, value = v})
    end
  end

  if msg.Tags then
    if isArray(msg.Tags) then
      for _, o in ipairs(msg.Tags) do
        table.insert(spawn.Tags, o)
      end
    else
      for k, v in pairs(msg.Tags) do
        table.insert(spawn.Tags, {name = k, value = v})
      end
    end
  end

  -- If running in an environment without the AOS Handlers module, do not add
  -- the after and receive functions to the spawn.
  if not Handlers then return spawn end

  -- clone spawn info and add to outbox
  local extSpawn = {}
  for k, v in pairs(spawn) do extSpawn[k] = v end

  table.insert(ao.outbox.Spawns, extSpawn)

  -- add 'after' callback to returned table
  -- local result = {}
  spawn.onReply = function(callback)
    Handlers.once({
      Action = "Spawned",
      From = ao.id,
      ["Reference"] = spawnRef
    }, callback)
  end

  spawn.receive = function(timeout)
    return Handlers.receive({
      Action = "Spawned",
      From = ao.id,
      ["Reference"] = spawnRef
    }, timeout)
  end

  return spawn
end

function ao.assign(assignment)
  assert(type(assignment) == 'table', 'assignment should be a table')
  assert(type(assignment.Processes) == 'table', 'Processes should be a table')
  assert(type(assignment.Message) == "string", "Message should be a string")
  table.insert(ao.outbox.Assignments, assignment)
end

-- The default security model of AOS processes: Trust all and *only* those
-- on the ao.authorities list.
function ao.isTrusted(msg)
  for _, authority in ipairs(ao.authorities) do
    if msg.From == authority then return true end
    if msg.Owner == authority then return true end
  end
  return false
end

function ao.result(result)
  if not result then result = {} end

  -- if error then only send the Error to CU
  if ao.outbox.Error or result.Error then
    return {Error = result.Error or ao.outbox.Error}
  end
  return {
    Output = result.Output or ao.outbox.Output or {},
    Messages = ao.outbox.Messages or {},
    Spawns = ao.outbox.Spawns or {},
    Assignments = ao.outbox.Assignments or {}
  }
end

function ao.normalize_tags(msg)
  local inputs = {}

  for _, o in ipairs(msg.Tags) do
  if not inputs[o.name] then
    inputs[o.name] = o.value
  end
  end

  return inputs
end

function ao.add_message_actions(msg)
  function msg.reply(replyMsg)
    replyMsg.Target = msg["Reply-To"] or (replyMsg.Target or msg.From)
    replyMsg["X-Reference"] = msg["X-Reference"] or msg.Reference
    replyMsg["X-Origin"] = msg["X-Origin"] or nil
    replyMsg["Response-For"] = msg.Action

    return ao.send(replyMsg)
  end

  function msg.forward(target, forwardMsg)
    -- Clone the message and add forwardMsg tags
    local newMsg =  ao.sanitize(msg)
    forwardMsg = forwardMsg or {}

    for k,v in pairs(forwardMsg) do
      newMsg[k] = v
    end

    -- Set forward-specific tags
    newMsg.Target = target
    newMsg["Reply-To"] = msg["Reply-To"] or msg.From
    newMsg["X-Reference"] = msg["X-Reference"] or msg.Reference
    newMsg["X-Origin"] = msg["X-Origin"] or msg.From

    ao.send(newMsg)
  end
end

return ao
