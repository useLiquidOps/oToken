local mod = {}

-- Applies a given map of mock modules
---@param mock_modules table<string, any> Mock modules
function mod.mock_require(mock_modules)
  local original_require = require

  require = function (module_name)
    if mock_modules[module_name] then
      return mock_modules[module_name]
    end

    return original_require(module_name)
  end
end

return mod
