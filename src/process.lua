local process = { _version = "0.0.1" }

local ao = require ".utils.ao"

function process.handle(msg, env)
  assert(ao.isTrusted(msg), "ao Message is not trusted")

  ao.normalize_tags(msg)

  return env.result({
    Output = ""
  })
end

return process
