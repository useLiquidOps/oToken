-- Copyright (c) 2024 Forward Research
-- Code from the aos codebase: https://github.com/permaweb/aos

local handlers = { _version = "0.0.5" }
local coroutine = require('coroutine')
local utils = require('.utils.utils')

handlers.utils = require('.utils.handlers-utils')
-- if update we need to keep defined handlers
if Handlers then
  handlers.list = Handlers.list or {}
  handlers.coroutines = Handlers.coroutines or {}
else
  handlers.list = {}
  handlers.coroutines = {}

end
handlers.onceNonce = 0


local function findIndexByProp(array, prop, value)
  for index, object in ipairs(array) do
    if object[prop] == value then
      return index
    end
  end
  return nil
end

local function assertAddArgs(name, pattern, handle, maxRuns)
  assert(
    type(name) == 'string' and
    (type(pattern) == 'function' or type(pattern) == 'table' or type(pattern) == 'string'),
    'Invalid arguments given. Expected: \n' ..
    '\tname : string, ' ..
    '\tpattern : Action : string | MsgMatch : table,\n' ..
    '\t\tfunction(msg: Message) : {-1 = break, 0 = skip, 1 = continue},\n' ..
    '\thandle(msg : Message) : void) | Resolver,\n' ..
    '\tMaxRuns? : number | "inf" | nil')
end

function handlers.generateResolver(resolveSpec)
  return function(msg)
    -- If the resolver is a single function, call it.
    -- Else, find the first matching pattern (by its matchSpec), and exec.
    if type(resolveSpec) == "function" then
      return resolveSpec(msg)
    else
        for matchSpec, func in pairs(resolveSpec) do
            if utils.matchesSpec(msg, matchSpec) then
                return func(msg)
            end
        end
    end
  end
end

-- Returns the next message that matches the pattern
-- This function uses Lua's coroutines under-the-hood to add a handler, pause,
-- and then resume the current coroutine. This allows us to effectively block
-- processing of one message until another is received that matches the pattern.
function handlers.receive(pattern)
  local self = coroutine.running()
  handlers.once(pattern, function (msg)
      coroutine.resume(self, msg)
  end)
  return coroutine.yield(pattern)
end

function handlers.once(...)
  local name, pattern, handle
  if select("#", ...) == 3 then
    name = select(1, ...)
    pattern = select(2, ...)
    handle = select(3, ...)
  else
    name = "_once_" .. tostring(handlers.onceNonce)
    handlers.onceNonce = handlers.onceNonce + 1
    pattern = select(1, ...)
    handle = select(2, ...)
  end
  handlers.add(name, pattern, handle, 1)
end

function handlers.add(...)
  local args = select("#", ...)
  local name = select(1, ...)
  local pattern = select(1, ...)
  local handle = select(2, ...)

  local maxRuns, errorHandler

  if args >= 3 then
    pattern = select(2, ...)
    handle = select(3, ...)
  end
  if args >= 4 then maxRuns = select(4, ...) end
  if args == 5 then errorHandler = select(5, ...) end

  assertAddArgs(name, pattern, handle, maxRuns)
  
  handle = handlers.generateResolver(handle)
  
  -- update existing handler by name
  local idx = findIndexByProp(handlers.list, "name", name)
  if idx ~= nil and idx > 0 then
    -- found update
    handlers.list[idx].pattern = pattern
    handlers.list[idx].handle = handle
    handlers.list[idx].maxRuns = maxRuns
    handlers.list[idx].errorHandler = errorHandler
  else
    -- not found then add    
    table.insert(handlers.list, { pattern = pattern, handle = handle, name = name, maxRuns = maxRuns, errorHandler = errorHandler })

  end
  return #handlers.list
end

function handlers.append(...)
  local args = select("#", ...)
  local name = select(1, ...)
  local pattern = select(1, ...)
  local handle = select(2, ...)

  local maxRuns, errorHandler

  if args >= 3 then
    pattern = select(2, ...)
    handle = select(3, ...)
  end
  if args >= 4 then maxRuns = select(4, ...) end
  if args == 5 then errorHandler = select(5, ...) end

  assertAddArgs(name, pattern, handle, maxRuns)
  
  handle = handlers.generateResolver(handle)
  -- update existing handler by name
  local idx = findIndexByProp(handlers.list, "name", name)
  if idx ~= nil and idx > 0 then
    -- found update
    handlers.list[idx].pattern = pattern
    handlers.list[idx].handle = handle
    handlers.list[idx].maxRuns = maxRuns
    handlers.list[idx].errorHandler = errorHandler
  else
    table.insert(handlers.list, { pattern = pattern, handle = handle, name = name, maxRuns = maxRuns, errorHandler = errorHandler })
  end

  
end

function handlers.prepend(...)
  local args = select("#", ...)
  local name = select(1, ...)
  local pattern = select(1, ...)
  local handle = select(2, ...)

  local maxRuns, errorHandler

  if args >= 3 then
    pattern = select(2, ...)
    handle = select(3, ...)
  end
  if args >= 4 then maxRuns = select(4, ...) end
  if args == 5 then errorHandler = select(5, ...) end

  assertAddArgs(name, pattern, handle, maxRuns)

  handle = handlers.generateResolver(handle)

  -- update existing handler by name
  local idx = findIndexByProp(handlers.list, "name", name)
  if idx ~= nil and idx > 0 then
    -- found update
    handlers.list[idx].pattern = pattern
    handlers.list[idx].handle = handle
    handlers.list[idx].maxRuns = maxRuns
    handlers.list[idx].errorHandler = errorHandler
  else  
    table.insert(handlers.list, 1, { pattern = pattern, handle = handle, name = name, maxRuns = maxRuns, errorHandler = errorHandler })
  end

  
end

function handlers.before(handleName)
  assert(type(handleName) == 'string', 'Handler name MUST be a string')

  local idx = findIndexByProp(handlers.list, "name", handleName)
  return {
    add = function (name, pattern, handle, maxRuns, errorHandler) 
      assertAddArgs(name, pattern, handle, maxRuns)
      
      handle = handlers.generateResolver(handle)
      
      if idx then
        table.insert(handlers.list, idx, { pattern = pattern, handle = handle, name = name, maxRuns = maxRuns, errorHandler = errorHandler })
      end
      
    end
  }
end

function handlers.after(handleName)
  assert(type(handleName) == 'string', 'Handler name MUST be a string')
  local idx = findIndexByProp(handlers.list, "name", handleName)
  return {
    add = function (name, pattern, handle, maxRuns, errorHandler)
      assertAddArgs(name, pattern, handle, maxRuns)
      
      handle = handlers.generateResolver(handle)
      
      if idx then
        table.insert(handlers.list, idx + 1, { pattern = pattern, handle = handle, name = name, maxRuns = maxRuns, errorHandler = errorHandler })
      end
      
    end
  }

end

function handlers.remove(name)
  assert(type(name) == 'string', 'name MUST be string')
  if #handlers.list == 1 and handlers.list[1].name == name then
    handlers.list = {}
    
  end

  local idx = findIndexByProp(handlers.list, "name", name)
  table.remove(handlers.list, idx)
  
end

--- return 0 to not call handler, -1 to break after handler is called, 1 to continue
function handlers.evaluate(msg, env)
  local handled = false
  assert(type(msg) == 'table', 'msg is not valid')
  assert(type(env) == 'table', 'env is not valid')
  
  for _, o in ipairs(handlers.list) do
    if o.name ~= "_default" then
      local match = utils.matchesSpec(msg, o.pattern)
      if not (type(match) == 'number' or type(match) == 'string' or type(match) == 'boolean') then
        error("Pattern result is not valid, it MUST be string, number, or boolean")
      end
      
      -- handle boolean returns
      if type(match) == "boolean" and match == true then
        match = -1
      elseif type(match) == "boolean" and match == false then
        match = 0
      end

      -- handle string returns
      if type(match) == "string" then
        if match == "continue" then
          match = 1
        elseif match == "break" then
          match = -1
        else
          match = 0
        end
      end

      if match ~= 0 then
        if match < 0 then
          handled = true
        end
        -- each handle function can accept, the msg, env
        local status, err = pcall(o.handle, msg, env)
        if not status then
          if not o.errorHandler then error(err)
          else pcall(o.errorHandler, msg, env, err) end
        end
        -- remove handler if maxRuns is reached. maxRuns can be either a number or "inf"
        if o.maxRuns ~= nil and o.maxRuns ~= "inf" then
          o.maxRuns = o.maxRuns - 1
          if o.maxRuns == 0 then
            handlers.remove(o.name)
          end
        end
      end
      if match < 0 then
        return handled
      end
    end
  end
  -- do default
  if not handled then
    local idx = findIndexByProp(handlers.list, "name", "_default")
    handlers.list[idx].handle(msg,env)
  end
end

return handlers