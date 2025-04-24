-- Copyright (c) 2024 Forward Research
-- Code from the aos codebase: https://github.com/permaweb/aos

local bint = require ".utils.bint"(1024)

local utils = { _version = "0.0.5" }

-- Given a pattern, a value, and a message, returns whether there is a pattern match
---@param pattern Pattern|nil The pattern to match
---@param value Pattern The value to check for in the pattern
---@param msg Message The message to check for the pattern
---@return boolean
function utils.matchesPattern(pattern, value, msg)
  -- If the key is not in the message, then it does not match
  if(not pattern) then
    return false
  end
  -- if the patternMatchSpec is a wildcard, then it always matches
  if pattern == '_' then
    return true
  end
  -- if the patternMatchSpec is a function, then it is executed on the tag value
  if type(pattern) == "function" then
    if pattern(value, msg) then
      return true
    else
      return false
    end
  end
  
  -- if the patternMatchSpec is a string, check it for special symbols (less `-` alone)
  -- and exact string match mode
  if (type(pattern) == 'string') then
    if string.match(pattern, "[%^%$%(%)%%%.%[%]%*%+%?]") then
      if string.match(value, pattern) then
        return true
      end
    else
      if value == pattern then
        return true
      end
    end
  end

  -- if the pattern is a table, recursively check if any of its sub-patterns match
  if type(pattern) == 'table' then
    for _, subPattern in pairs(pattern) do
      if utils.matchesPattern(subPattern, value, msg) then
        return true
      end
    end
  end

  return false
end

-- Given a message and a spec, returns whetehr there is a spec match
---@param msg Message The message to check for in the spec
---@param spec Spec The spec to check for in the message
---@return boolean
function utils.matchesSpec(msg, spec)
  if type(spec) == 'function' then
    return spec(msg)
  -- If the spec is a table, step through every key/value pair in the pattern and check if the msg matches
  -- Supported pattern types:
  --   - Exact string match
  --   - Lua gmatch string
  --   - '_' (wildcard: Message has tag, but can be any value)
  --   - Function execution on the tag, optionally using the msg as the second argument
  --   - Table of patterns, where ANY of the sub-patterns matching the tag will result in a match
  end

  if type(spec) == 'table' then
    for key, pattern in pairs(spec) do
      if not msg[key] then
        return false
      end
      if not utils.matchesPattern(pattern, msg[key], msg) then
        return false
      end
    end
    return true
  end

  if type(spec) == 'string' and msg.Action and msg.Action == spec then
    return true
  end

  return false
end

local function isArray(table)
  if type(table) == "table" then
    local maxIndex = 0

    for k, _ in pairs(table) do
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

-- Allows currying usage of a function
---@param fn function
---@param arity number
---@return function
utils.curry = function (fn, arity)
  assert(type(fn) == "function", "function is required as first argument")
  arity = arity or debug.getinfo(fn, "u").nparams
  if arity < 2 then return fn end

  return function (...)
    local args = {...}

    if #args >= arity then
      return fn(table.unpack(args))
    else
      return utils.curry(function (...)
        return fn(table.unpack(args),  ...)
      end, arity - #args)
    end
  end
end

-- Concat two Array Tables
---@generic T : unknown
---@param a T[] First array
---@param b T[] Second array
---@return T[]
function utils.concat(a, b)
  assert(type(a) == "table", "first argument should be a table that is an array")
  assert(type(b) == "table", "second argument should be a table that is an array")
  assert(isArray(a), "first argument should be a table")
  assert(isArray(b), "second argument should be a table")

  local result = {}

  for i = 1, #a do
    result[#result + 1] = a[i]
  end
  for i = 1, #b do
    result[#result + 1] = b[i]
  end

  return result
end

-- Reduce executes the provided reducer function for all array elements, finally providing one (unified) result
---@generic T : unknown
---@param fn fun(accumulator: T, current: T, key: integer): T Provided reducer function
---@param initial T? Initial value
---@param t T[] Array to reduce
---@return T
function utils.reduce(fn, initial, t)
  assert(type(fn) == "function", "first argument should be a function that accepts (result, value, key)")
  assert(type(t) == "table" and isArray(t), "third argument should be a table that is an array")

  local result = initial

  for k, v in pairs(t) do
    if result == nil then
      result = v
    else
      result = fn(result, v, k)
    end
  end

  return result
end

-- Create a new array filled with the results of calling the provided map function on each element in the array
---@generic T : unknown
---@generic H : unknown
---@param fn fun(val: T, key: unknown): H The map function. It receives the current array element and key
---@param data T[] The array to map
---@return H[]
function utils.map(fn, data)
  assert(type(fn) == "function", "first argument should be a unary function")
  assert(type(data) == "table" and isArray(data), "second argument should be an Array")

  local function map (result, v, k)
    result[k] = fn(v, k)
    return result
  end

  return utils.reduce(map, {}, data)
end

-- This function creates a new array from a portion of the original, only keeping the elements that passed a provided filter function's test
---@generic T : unknown
---@param fn fun(val: T): boolean Filter function
---@param data T[] Array to filter
---@return T[]
function utils.filter(fn, data)
  assert(type(fn) == "function", "first argument should be a unary function")
  assert(type(data) == "table" and isArray(data), "second argument should be an Array")

  local function filter(result, v, _k)
    if fn(v) then
      table.insert(result, v)
    end

    return result
  end

  return utils.reduce(filter, {}, data)
end

-- This function returns the first element that matches in a provided function
---@generic T : unknown
---@param fn fun(val: T): boolean The find function that receives the current element and returns true if it matches, false if it doesn't
---@param t T[] Array to find the element in
---@return T|nil, integer|nil
function utils.find(fn, t)
  assert(type(fn) == "function", "first argument should be a unary function")
  assert(type(t) == "table", "second argument should be a table that is an array")

  for i, v in pairs(t) do
    if fn(v) then
      return v, i
    end
  end
end

-- Checks if a specified property of a table equals with the provided value
---@param propName string Name of the property to check
---@param value unknown Expected value
---@param object table Table to check
---@return boolean
function utils.propEq(propName, value, object)
  assert(type(propName) == "string", "first argument should be a string")
  -- assert(type(value) == "string", "second argument should be a string")
  assert(type(object) == "table", "third argument should be a table<object>")

  return object[propName] == value
end

-- Puts an array in reverse order
---@generic T : unknown
---@param data T[]
---@returns T[]
function utils.reverse(data)
  assert(type(data) == "table", "argument needs to be a table that is an array")

  return utils.reduce(
    function (result, v, i)
      result[#data - i + 1] = v

      return result
    end,
    {},
    data
  )
end

-- Chain multiple array mutations together and execute them in reverse order on the provided array
---@param ... function
---@return unknown
function utils.compose(...)
  local mutations = utils.reverse({...})

  return function (v)
    local result = v

    for _, fn in pairs(mutations) do
      assert(type(fn) == "function", "each argument needs to be a function")
      result = fn(result)
    end

    return result
  end
end

-- Returns the property value that belongs to the property name provided from an object
---@generic T
---@param propName string Name of the property to return
---@param object table The table to return the property value from
---@return T
function utils.prop(propName, object)
  return object[propName]
end

-- Checks if an array includes a specific value (of primitive type)
---@param val unknown Value to check for
---@param t unknown[] Array to find the value in
---@return boolean
function utils.includes(val, t)
  assert(type(t) == "table", "argument needs to be a table")

  return utils.find(function (v) return v == val end, t) ~= nil
end

-- Get the keys of a table as an array
---@generic T : unknown
---@param t table<T, unknown>
---@return T[]
function utils.keys(t)
  assert(type(t) == "table", "argument needs to be a table")

  local keys = {}

  for key in pairs(t) do
    table.insert(keys, key)
  end

  return keys
end

-- Get the values of a table as an array
---@generic T : unknown
---@param t table<unknown, T>
---@return T[]
function utils.values(t)
  assert(type(t) == "table", "argument needs to be a table")

  local values = {}

  -- get values
  for _, value in pairs(t) do
    table.insert(values, value)
  end

  return values
end

-- Turn a floating point number
---@param raw number Value to represent as a bigint
---@param floatMul number? Optional multiplier
function utils.floatBintRepresentation(raw, floatMul)
  if not floatMul then floatMul = 100000 end

  -- multiply the raw value by the floatMul
  -- we do this, so that we can calculate with
  -- more precise ratios, while using bigintegers
  -- later the final result needs to be handled
  -- according to the multiplier
  local repr = bint(raw * floatMul // 1)

  return repr, floatMul
end

-- Create a pretty error message from any Lua error 
-- (returns the pretty error and the raw stringified error)
---@param err unknown Original error message
function utils.prettyError(err)
  local rawError = tostring(err)

  return string.gsub(rawError, "%[[%w_.\" ]*%]:%d*: ", ""), rawError
end

-- Convert a lua number to a string
---@param val number The value to convert
function utils.floatToString(val)
  return string.format("%.17f", val):gsub("0+$", ""):gsub("%.$", "")
end

-- Convert a biginteger with a denomination to a float
---@param val Bint Bigint value
---@param denomination number Denomination
function utils.bintToFloat(val, denomination)
  local stringVal = tostring(val)
  local len = #stringVal

  if stringVal == "0" then return 0.0 end

  -- if denomination is greater than or equal to the string length, prepend "0."
  if denomination >= len then
    return tonumber("0." .. string.rep("0", denomination - len) .. stringVal)
  end

  -- insert decimal point at the correct position from the back
  local integer_part = string.sub(stringVal, 1, len - denomination)
  local fractional_part = string.sub(stringVal, len - denomination + 1)

  return tonumber(integer_part .. "." .. fractional_part)
end

-- Perform unsigned integer division, but rounding upwards
---@param x Bint
---@param y Bint
---@return Bint
function utils.udiv_roundup(x, y)
  return bint.udiv(
    x + y - bint.one(),
    y
  )
end

return utils
