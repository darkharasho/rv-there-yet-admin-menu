local config = require("mod.scripts.lib.config")
local log = require("mod.scripts.lib.log")

local function quiet(collected)
  return log.new{ name = "T", level = "DEBUG", sink = function(s) collected[#collected+1] = s end }
end

describe("config", function()
  it("parses keys case-insensitively and skips comments", function()
    local t = config.parse_ini("; note\nHotkey = F4\n# other\nHealAmount=50\n")
    assert.equal("F4", t.hotkey)
    assert.equal("50", t.healamount)
  end)

  it("skips section headers", function()
    local t = config.parse_ini("[General]\nHotkey = F4\n[Other]\nHealAmount=50\n")
    assert.equal("F4", t.hotkey)
    assert.equal("50", t.healamount)
  end)

  it("uses defaults when the ini is empty", function()
    local cfg = config.resolve({}, quiet({}))
    assert.equal("F3", cfg.hotkey)
    assert.is_true(cfg.hotkey_valid)
    assert.is_true(cfg.confirm_destructive)
  end)

  it("falls back to the default hotkey and warns on a bad key name", function()
    local lines = {}
    local cfg = config.resolve({ hotkey = "F27" }, quiet(lines))
    assert.equal("F3", cfg.hotkey)
    assert.is_false(cfg.hotkey_valid)
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("F27"))
    assert.truthy(joined:find("F3"))
  end)

  it("clamps heal amount into 1..1000", function()
    assert.equal(1000, config.resolve({ healamount = "99999" }, quiet({})).heal_amount)
    assert.equal(1, config.resolve({ healamount = "-5" }, quiet({})).heal_amount)
  end)

  it("reads booleans in the forms the community uses", function()
    for _, v in ipairs({ "0", "false", "no", "off" }) do
      assert.is_false(config.resolve({ confirmdestructive = v }, quiet({})).confirm_destructive)
    end
    for _, v in ipairs({ "1", "yes", "on" }) do
      assert.is_true(config.resolve({ confirmdestructive = v }, quiet({})).confirm_destructive)
    end
  end)

  it("falls back to the default heal amount and warns on a non-numeric value", function()
    local lines = {}
    local cfg = config.resolve({ healamount = "fifty" }, quiet(lines))
    assert.equal(100, cfg.heal_amount)
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("fifty"))
    assert.truthy(joined:find("100"))
  end)

  it("falls back to the default confirm_destructive and warns on a garbage value", function()
    local lines = {}
    local cfg = config.resolve({ confirmdestructive = "maybe" }, quiet(lines))
    assert.is_true(cfg.confirm_destructive)
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("maybe"))
  end)

  it("falls back to the default log level and warns on an unrecognized name", function()
    -- resolve() must return a validated cfg: a startup banner printing
    -- cfg.log_level must not tell the user BANANA while running at INFO.
    local lines = {}
    local cfg = config.resolve({ loglevel = "BANANA" }, quiet(lines))
    assert.equal("INFO", cfg.log_level)
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("BANANA"))
  end)

  it("accepts a valid log level in any case", function()
    assert.equal("DEBUG", config.resolve({ loglevel = "debug" }, quiet({})).log_level)
  end)

  it("resolves without a logger instead of erroring", function()
    -- The only uncaught error that was reachable under mod/: every
    -- resolver indexes the logger to warn.
    local cfg = config.resolve({
      hotkey = "F27", loglevel = "BANANA",
      confirmdestructive = "maybe", healamount = "fifty",
    })
    assert.equal("F3", cfg.hotkey)
    assert.is_false(cfg.hotkey_valid)
    assert.equal("INFO", cfg.log_level)
    assert.is_true(cfg.confirm_destructive)
    assert.equal(100, cfg.heal_amount)
  end)

  it("tolerates a logger that is not a logger", function()
    assert.equal("F3", config.resolve({ hotkey = "F27" }, "not a logger").hotkey)
  end)
end)
