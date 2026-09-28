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

  it("set_level after construction changes what is emitted", function()
    logger:info("hidden at WARN")
    assert.equal(0, #lines)
    logger:set_level("DEBUG")
    logger:debug("now shown")
    assert.equal(1, #lines)
    assert.truthy(lines[1]:find("DEBUG"))
    logger:set_level("ERROR")
    logger:warn("hidden again")
    assert.equal(1, #lines)
  end)

  it("set_level falls back to INFO for an unknown name", function()
    logger:set_level("BANANA")
    logger:debug("hidden"); logger:info("shown")
    assert.equal(1, #lines)
    assert.truthy(lines[1]:find("INFO"))
  end)

  it("emits at DEBUG when constructed at DEBUG", function()
    local l = log.new{ name = "T", level = "DEBUG", sink = function(s) lines[#lines+1] = s end }
    l:debug("verbose")
    assert.equal(1, #lines)
    assert.truthy(lines[1]:find("DEBUG"))
    assert.truthy(lines[1]:find("verbose"))
  end)

  it("a throwing sink never escapes the logger", function()
    -- UE4SS's print can throw once the log handle is torn down. The error
    -- would otherwise escape through ue.lua's warn() into a HUD hook or
    -- key-bind callback on the game thread.
    local l = log.new{ name = "T", level = "DEBUG", sink = function() error("log handle closed") end }
    l:error("still fine")
    l:warn("still fine")
    l:info("still fine")
    l:debug("still fine")
  end)

  it("a non-callable sink never escapes the logger", function()
    local l = log.new{ name = "T", level = "DEBUG", sink = "not a function" }
    l:error("still fine")
  end)
end)
