-- Copyright (c) 2024 Forward Research
-- Code from the aos codebase: https://github.com/permaweb/aos

local _utils = { _version = "0.0.1" }

local utils = require('.utils.utils')
local ao = require(".utils.ao")

function _utils.hasMatchingTag(name, value)
  assert(type(name) == 'string' and type(value) == 'string', 'invalid arguments: (name : string, value : string)')

  return function (msg) 
    return msg.Tags[name] == value 
  end
end

function _utils.hasMatchingTagOf(name, values)
  assert(type(name) == 'string' and type(values) == 'table', 'invalid arguments: (name : string, values : string[])')
  return function (msg)
    for _, value in ipairs(values) do
      local patternResult = Handlers.utils.hasMatchingTag(name, value)(msg)

      if patternResult ~= 0 and patternResult ~= false and patternResult ~= "skip" then
        return patternResult
      end
    end

    return 0
  end
end

function _utils.hasMatchingData(value)
  assert(type(value) == 'string', 'invalid arguments: (value : string)')
  return function (msg)
    return msg.Data == value
  end
end

function _utils.reply(input) 
  assert(type(input) == 'table' or type(input) == 'string', 'invalid arguments: (input : table or string)')
  return function (msg)
    if type(input) == 'string' then
      ao.send({Target = msg.From, Data = input})
      return
    end
    ao.send({Target = msg.From, Tags = input })
  end
end

function _utils.continue(pattern)
  return function (msg)
    local match = utils.matchesSpec(msg, pattern)

    if not match or match == 0 or match == "skip" then
      return match
    end
    return 1
  end
end

return _utils