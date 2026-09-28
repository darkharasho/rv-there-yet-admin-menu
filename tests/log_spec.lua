local log = require("mod.scripts.lib.log")

describe("log", function()
  local lines, logger
  before_each(function()
    lines = {}
    logger = log.new{ name = "T", level = "WARN", sink = function(s) lines[#lines+1] = s end }
  end)

  it("suppresses messages below the level", function()
    logger:info("quiet")
    assert.equal(0, #lines)
  end)

  it("emits messages at or above the level", function()
    logger:error("loud")
    assert.equal(1, #lines)
    assert.truthy(lines[1]:find("%[T%]"))
    assert.truthy(lines[1]:find("ERROR"))
    assert.truthy(lines[1]:find("loud"))
  end)

  it("does not append a trailing newline (the default sink is print)", function()
    logger:error("loud")
    assert.equal(1, #lines)
    assert.is_nil(lines[1]:find("\n$"))
  end)

  it("falls back to INFO for an unknown level name", function()
    local l = log.new{ name = "T", level = "BANANA", sink = function(s) lines[#lines+1] = s end }
    l:info("shown"); l:debug("hidden")
    assert.equal(1, #lines)
  end)
end)
