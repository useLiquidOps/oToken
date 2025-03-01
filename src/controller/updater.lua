---@type HandlerFunction
local function update(msg)
  -- load update
  local src = msg.Data
  local install, err = load(src, "update", "t", _G)

  -- check if the update is valid
  assert(not err and type(install) == "function", err or "Unknown error (no install function returned)")

  -- install the update
  install()

  msg.reply({ Updated = "true" })
end

return update