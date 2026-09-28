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
  end)
end)
