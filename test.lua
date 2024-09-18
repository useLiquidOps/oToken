local utils = require "src.utils.utils"

local test = {
  { ticker = "ar" },
  { ticker = "eth "},
  { ticker = "ar" }
}

local res = utils.map(
  function (el)
    return el.ticker
  end,
  test
)

for k, v in ipairs(res) do
  print(k .. "=" .. v)
end
