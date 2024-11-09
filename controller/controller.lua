local utils = require ".utils"
local json = require "json"
local assertions = {}
local tokens = {}

-- oToken module ID
Module = ""

-- oracle id and tolerance
Oracle = ""
MaxOracleDelay = 1200000

-- liquidops logo tx id
ProtocolLogo = ""

-- token - oToken map
---@type table<string, string>
Tokens = {}

Handlers.add(
  "list",
  { From = ao.id, Action = "List" },
  function (msg)
    -- token to be listed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )

    -- check configuration
    assert(
      tonumber(msg.Tags["Collateral-Factor"]) ~= nil,
      "Invalid collateral factor"
    )
    assert(
      tonumber(msg.Tags["Liquidation-Threshold"]) ~= nil,
      "Invalid liquidation threshold"
    )
    assert(
      tonumber(msg.Tags["Base-Rate"]) ~= nil,
      "Invalid base rate"
    )
    assert(
      tonumber(msg.Tags["Init-Rate"]) ~= nil,
      "Invalid init rate"
    )

    -- check if token is supported
    local supported, info = tokens.isSupported(token)

    assert(supported, "Token not supported by the protocol")

    -- spawn logo
    local logo = tokens.spawnProtocolLogo(info.Tags.Logo)

    -- the oToken configuration
    local config = {
      ["Collateral-Id"] = token,
      ["Collateral-Ticker"] = info.Tags.Ticker,
      ["Collateral-Name"] = info.Tags.Name,
      ["Collateral-Denomination"] = info.Tags.Denomination,
      ["Collateral-Factor"] = msg.Tags["Collateral-Factor"],
      ["Liquidation-Threshold"] = msg.Tags["Liquidation-Threshold"],
      ["Base-Rate"] = msg.Tags["Base-Rate"],
      ["Init-Rate"] = msg.Tags["Init-Rate"],
      Oracle = Oracle,
      ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
      Friends = json.encode(utils.values(Tokens)),
      Logo = logo
    }

    -- spawn new oToken process
    local spawnResult = ao.spawn(Module, config).receive()

    -- add token to tokens list
    Tokens[token] = spawnResult.Tags.Process

    msg.reply({
      Action = "Token-Listed",
      Token = token,
      ["Spawned-Id"] = spawnResult.Tags.Process,
      Data = json.encode(config)
    })
  end
)

Handlers.add(
  "unlist",
  { From = ao.id, Action = "Unlist" },
  function (msg)
    -- token to be removed
    local token = msg.Tags.Token

    assert(
      assertions.isAddress(token),
      "Invalid token address"
    )
    assert(Tokens[token] ~= nil, "Token is not listed")

    -- id of the oToken for this token
    local oToken = Tokens[token]

    -- unlist
    Tokens[token] = nil

    msg.reply({
      Action = "Token-Unlisted",
      Token = token,
      ["Removed-Id"] = oToken
    })
  end
)

Handlers.add(
  "liquidate",
  { Action = "Credit-Notice", ["X-Action"] = "Liquidate" },
  function (msg)
    -- liquidation target
    local target = msg.Tags["X-Target"]

    assert(
      assertions.isAddress(target),
      "Invalid liquidation target"
    )

    -- token to be liquidated 
    -- (the token that is paying for the loan = transferred token)
    local liquidatedToken = msg.From

    assert(
      Tokens[liquidatedToken] ~= nil,
      "Cannot liquidate the incoming token as it is not listed"
    )

    -- the token of the position that will be liquidated
    -- (this will be sent to the liquidator as a reward)
    local positionToken = msg.Tags["X-Position-Token"]

    assert(
      Tokens[positionToken] ~= nil,
      "Cannot liquidate for the position token as it is not listed"
    )

    -- TODO: check user position

    -- TODO: check if user position includes the desired token

    -- TODO: check queue

    -- TODO: queue the liquidation at this point, because
    -- the user position has been checked, so the liquidation is valid
    -- we don't want anyone to be able to liquidate from this point

    -- TODO: step 1: liquidate the loan

    -- TODO: check loan liquidation result
    -- TODO: timeout here? (what if this doesn't return in time, the liquidation remains in a pending state)

    -- TODO: step 2: liquidate the position (transfer out the reward)

    -- TODO: send confirmation to the liquidator
  end
)

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function assertions.isAddress(addr)
  if not type(addr) == "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "[A-z0-9_-]+") == nil then return false end

  return true
end

-- Check if token is supported by the protocol
-- (token supports aos 2.0 replies and replies with a proper info response)
-- Returns if the token is supported and the token info
---@param addr string Token address
function tokens.isSupported(addr)
  -- send info request
  ao.send({
    Target = addr,
    Action = "Info",
  })

  -- wait for proper response
  local res = Handlers.receive({
    From = addr,
    Ticker = "^.+$",
    Name = "^.+$",
    Denomination = "^.+$"
  })

  local repliesSupported = res.Tags["X-Reference"] ~= nil

  local denomination = tonumber(res.Tags.Denomination)
  local validDenomination = denomination ~= nil and
    denomination == denomination // 1 and
    denomination > 0 and
    denomination <= 18

  return repliesSupported and validDenomination, res
end

-- Spawn a LiquidOps themed logo for the oToken
-- (if the collateral doesn't have a logo, the protocol
-- will use the liquidops logo by default)
---@param collateralLogo string? The logo of the collateral token
function tokens.spawnProtocolLogo(collateralLogo)
  if not collateralLogo then return ProtocolLogo end

  -- the base logo on two parts
  local logoPart1 = '<svg width="209" height="209" viewBox="0 0 209 209" fill="none" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><path fill-rule="evenodd" clip-rule="evenodd" d="M104.338 167.45C69.4822 167.45 41.2261 139.194 41.2261 104.338C41.2261 69.4822 69.4822 41.2261 104.338 41.2261C139.194 41.2261 167.45 69.4822 167.45 104.338C167.45 139.194 139.194 167.45 104.338 167.45Z" fill="white"/><path fill-rule="evenodd" clip-rule="evenodd" d="M0.0258105 104.338C0.025808 161.948 46.7279 208.65 104.338 208.65C161.948 208.65 208.65 161.948 208.65 104.338C208.65 46.728 161.948 0.0258769 104.338 0.0258743C46.7279 0.0258718 0.025813 46.728 0.0258105 104.338Z" fill="url(#paint0_radial_967_225)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M8.14144 144.709C26.0007 187.415 70.2136 213.262 116.097 207.999C101.792 198.058 31.5666 127.163 98.1277 96.6245C170.951 63.2132 166.399 24.8374 149.014 10.0751C127.427 -0.168817 102.228 -3.08861 77.34 3.58023C57.2243 8.97022 40.0649 19.8861 27.0574 34.257C14.6366 48.2947 5.9814 65.395 2.1366 83.3465C-0.233773 94.8415 -0.68376 106.868 1.04746 118.976C1.64542 122.737 2.47999 126.472 3.56051 130.162C4.69973 135.191 6.24463 140.047 8.14144 144.709Z" fill="url(#paint1_linear_967_225)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M147.996 9.59888C163.381 20.0038 201.307 50.7506 136.617 87.8522C65.7443 128.5 125.078 191.493 164.844 189.344C199.306 164.807 216.688 120.605 205.096 77.3404C196.749 46.1915 175.153 22.1313 147.996 9.59888Z" fill="url(#paint2_linear_967_225)"/><path d="M103.955 166.453C138.12 166.453 165.816 138.757 165.816 104.592C165.816 70.4275 138.12 42.7314 103.955 42.7314C69.7903 42.7314 42.0941 70.4275 42.0941 104.592C42.0941 138.757 69.7903 166.453 103.955 166.453Z" fill="white"/><path d="M103.955 166.453C138.12 166.453 165.816 138.757 165.816 104.592C165.816 70.4275 138.12 42.7314 103.955 42.7314C69.7903 42.7314 42.0941 70.4275 42.0941 104.592C42.0941 138.757 69.7903 166.453 103.955 166.453Z" fill="url(#pattern0_967_225)"/><path fill-rule="evenodd" clip-rule="evenodd" d="M148.419 61.5761C147.569 62.6188 146.666 63.6663 145.706 64.7176C136.092 75.2562 120.891 86.182 98.1336 96.623C64.7584 111.936 65.7745 137.395 76.8875 160.228C76.8875 160.228 76.8875 160.228 76.8875 160.228C56.291 150.187 42.1 129.046 42.1 104.591C42.1 70.426 69.7962 42.73 103.961 42.73C121.41 42.73 137.173 49.9547 148.419 61.5761Z" fill="url(#paint3_linear_967_225)" fill-opacity="0.15"/><path fill-rule="evenodd" clip-rule="evenodd" d="M156.213 74.3474C156.602 74.0134 156.983 73.68 157.357 73.3474C162.734 82.517 165.816 93.1947 165.816 104.592C165.816 134.49 144.607 159.433 116.413 165.198C98.3155 143.627 94.7809 111.846 136.617 87.8522" fill="url(#paint4_linear_967_225)" fill-opacity="0.2"/><defs><pattern id="pattern0_967_225" patternContentUnits="objectBoundingBox" width="1" height="1"><use xlink:href="#image0_967_225" transform="scale(0.0025)"/></pattern><radialGradient id="paint0_radial_967_225" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(104.338 104.338) rotate(-29.6192) scale(135.925 130.152)"><stop offset="0.5" stop-color="#B8B8FF"/><stop offset="1" stop-color="#DCDCFF"/></radialGradient><linearGradient id="paint1_linear_967_225" x1="79.895" y1="265.291" x2="79.895" y2="0" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><linearGradient id="paint2_linear_967_225" x1="267.473" y1="120.937" x2="44.7973" y2="120.937" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><linearGradient id="paint3_linear_967_225" x1="79.9008" y1="265.29" x2="79.9008" y2="-0.00146024" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><linearGradient id="paint4_linear_967_225" x1="267.473" y1="120.937" x2="44.7973" y2="120.937" gradientUnits="userSpaceOnUse"><stop stop-color="#4844EC"/><stop offset="1" stop-color="#766AFF"/></linearGradient><image id="image0_967_225" width="400" height="400" xlink:href="'
  local logoPart2 = '" preserveAspectRatio="xMidYMid slice"/></defs></svg>'

  -- message that spawns the logo
  -- we're sending this to ourselves
  ao.send({
    Target = ao.id,
    Action = "Spawn-Logo",
    ["Content-Type"] = "image/svg+xml",
    Data = logoPart1 .. "/" .. collateralLogo .. logoPart2
  })

  -- now receive the message we are sending ourselves
  ---@type Message
  local spawnedImage = Handlers.receive({
    From = ao.id,
    Reference = tostring(ao.reference)
  })

  return spawnedImage.Id
end
