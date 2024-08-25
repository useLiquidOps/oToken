local bint = require ".utils.bint"(1024)

local utils = {}
local mod = {}

---@type HandlerFunction
function mod.setup()
  ---@type Message
  local tokenInfo = ao.send({
    Target = Token,
    Action = "Info"
  }).receive()

  Name = "LiquidOps " .. tokenInfo.Tags.Name
  Ticker = "lo" .. tokenInfo.Tags.Ticker

  -- the wrapped token's denomination
  WrappedDenomination = tonumber(tokenInfo.Tags.Denomination)

  -- submit logo to arweave
  ao.send({
    Target = ao.id,
    Action = "Set-Logo",
    Data = utils.getLogo(tokenInfo.Tags.Logo)
  })

  -- set logo
  Handlers.once(
    { From = ao.id, Action = "Set-Logo" },
    function (msg) Logo = msg.Id end
  )

  Denomination = Denomination or 12
  Balances = Balances or {}
  TotalSupply = TotalSupply or bint.zero()
end

---@param msg Message
function mod.info(msg)
  msg.reply({
    Name = Name,
    Ticker = Ticker,
    Logo = Logo,
    Denomination = tostring(Denomination)
  })
end

---@param msg Message
function mod.total_supply(msg)
  msg.reply({
    ["Total-Supply"] = tostring(TotalSupply),
    Ticker = Ticker,
    Data = tostring(TotalSupply)
  })
end

-- Get logo image file
---@param originalLogo string Wrapped token logo id
function utils.getLogo(originalLogo)
  return [[<svg width="512" height="512" viewBox="0 0 512 512" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
    <g clip-path="url(#clip0_124_176)">
      <rect width="512" height="510.972" fill="url(#pattern0_124_176)"/>
      <path fill-rule="evenodd" clip-rule="evenodd" d="M418 457C396.461 457 379 439.539 379 418C379 396.461 396.461 379 418 379C439.539 379 457 396.461 457 418C457 439.539 439.539 457 418 457Z" fill="white"/>
      <path fill-rule="evenodd" clip-rule="evenodd" d="M379.278 418C379.278 439.385 396.615 456.722 418 456.722C439.385 456.722 456.722 439.385 456.722 418C456.722 396.614 439.386 379.278 418 379.278C396.615 379.278 379.278 396.614 379.278 418ZM354 418C354 453.346 382.654 482 418 482C453.346 482 482 453.346 482 418C482 382.654 453.346 354 418 354C382.654 354 354 382.654 354 418Z" fill="url(#paint0_radial_124_176)"/>
      <path fill-rule="evenodd" clip-rule="evenodd" d="M425.212 481.576C416.442 475.478 373.387 431.995 414.195 413.264C458.843 392.772 456.052 369.234 445.393 360.18C432.159 353.896 416.71 352.106 401.451 356.196C370.697 364.44 349.926 393.741 354.676 426.973C359.612 461.504 390.802 485.524 425.212 481.576Z" fill="url(#paint1_linear_124_176)"/>
      <path fill-rule="evenodd" clip-rule="evenodd" d="M445.043 360C454.413 366.366 477.512 385.176 438.112 407.875C394.947 432.743 431.085 471.282 455.304 469.967C476.293 454.956 486.88 427.913 479.819 401.444C474.736 382.387 461.583 367.667 445.043 360Z" fill="url(#paint2_linear_124_176)"/>
    </g>
    <defs>
      <pattern id="pattern0_124_176" patternContentUnits="objectBoundingBox" width="1" height="1">
        <use xlink:href="#image0_124_176" transform="matrix(0.0025 0 0 0.00250503 0 -0.00100603)"/>
      </pattern>
      <radialGradient id="paint0_radial_124_176" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(418 418) rotate(-29.6192) scale(83.3957 79.8542)">
        <stop offset="0.5" stop-color="#B6B5FF"/>
        <stop offset="1" stop-color="#DCDCFF"/>
      </radialGradient>
      <linearGradient id="paint1_linear_124_176" x1="403" y1="354" x2="403" y2="482" gradientUnits="userSpaceOnUse">
        <stop stop-color="#6D6AFF"/>
        <stop offset="0.5" stop-color="#4844EC"/>
        <stop offset="1" stop-color="#191994"/>
      </linearGradient>
      <linearGradient id="paint2_linear_124_176" x1="517.81" y1="428.116" x2="382.19" y2="428.116" gradientUnits="userSpaceOnUse">
        <stop stop-color="#4844EC"/>
        <stop offset="1" stop-color="#6D6AFF"/>
      </linearGradient>
      <clipPath id="clip0_124_176">
        <rect width="512" height="512" fill="white"/>
      </clipPath>
      <image id="image0_124_176" width="400" height="400" xlink:href="/]] .. originalLogo .. [["/>
    </defs>
  </svg>
  ]]
end

return mod
