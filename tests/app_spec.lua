package.path = "mod/scripts/?.lua;" .. package.path
local app_mod = require("lib.app")
local fake_ue = require("tests.support.fake_ue")

local function new_app(host)
  local ue = fake_ue.new()
  ue.objects.BP_FirstPersonPlayerController_C = {
    { IsLocalController = function() return true end, CheatManager = {
      TeleportToVehicle = function(self) self.hit = true return true end } } }
  if host then ue.objects.GameModeBase = { {} } end
  local drawn = {}
  local overlay = { render = function(_, v) drawn[#drawn + 1] = v end }
  local app = app_mod.new({ ue = ue, cfg = { hotkey = "F3", confirm_destructive = true }, overlay = overlay })
  app:bind_keys()
  return app, ue, drawn
end

describe("app keyboard wiring", function()
  it("binds the hotkey and all navigation keys", function()
    local _, ue = new_app(true)
    for _, k in ipairs({ "F3", "UP_ARROW", "DOWN_ARROW", "RETURN", "RIGHT_ARROW", "BACKSPACE", "LEFT_ARROW" }) do
      assert.is_function(ue.key_binds[k], k)
    end
  end)

  it("binds letters, digits and space for search", function()
    local _, ue = new_app(true)
    for _, k in ipairs({ "A", "Z", "ZERO", "NINE", "SPACE" }) do
      assert.is_function(ue.key_binds[k], k)
    end
    ue.key_binds.A()   -- closed menu: ignored, no error
  end)

  it("ignores navigation while closed and toggles with the hotkey", function()
    local app, ue, drawn = new_app(true)
    ue.key_binds.DOWN_ARROW()
    assert.equal(0, #drawn)
    ue.key_binds.F3()
    assert.is_true(app.menu:is_open())
    assert.equal("RV Admin", drawn[#drawn].title)
    ue.key_binds.F3()
    assert.is_false(app.menu:is_open())
    assert.is_nil(drawn[#drawn].title)
  end)

  it("runs an action selected with RETURN and shows its message", function()
    local app, ue = new_app(true)
    ue.key_binds.F3()
    ue.key_binds.RETURN()          -- Teleport ...
    ue.key_binds.RETURN()          -- Me to RV
    assert.equal("Teleported to RV", app.menu:view().message)
  end)

  it("backs out and closes at the root", function()
    local app, ue = new_app(true)
    ue.key_binds.F3()
    ue.key_binds.RIGHT_ARROW()
    assert.equal("Teleport", app.menu:view().title)
    ue.key_binds.LEFT_ARROW()
    ue.key_binds.BACKSPACE()
    assert.is_false(app.menu:is_open())
  end)
end)

describe("app mouse wiring", function()
  local function mouse_app(cfg_mouse)
    local ue = fake_ue.new()
    local pc = { bShowMouseCursor = false, ignore = {}, modes = {},
      IsLocalController = function() return true end,
      CheatManager = { TeleportToVehicle = function() return true end } }
    function pc:SetIgnoreLookInput(v) self.ignore[#self.ignore + 1] = v end
    ue.objects.BP_FirstPersonPlayerController_C = { pc }
    ue.objects.GameModeBase = { {} }
    local lib = {}
    function lib:SetInputMode_UIOnlyEx(p) p.modes[#p.modes + 1] = "UIOnly" end
    function lib:SetInputMode_GameOnly(p) p.modes[#p.modes + 1] = "GameOnly" end
    local loops = 0
    local env = {
      StaticFindObject = function() return lib end,
      LoopAsync = function() loops = loops + 1 end,
    }
    local hovered
    local overlay = { render = function() end, widget_object = function() return {} end,
      hovered_index = function() return hovered end }
    local app = app_mod.new({ ue = ue, env = env, overlay = overlay,
      cfg = { hotkey = "F3", confirm_destructive = true, mouse = cfg_mouse } })
    app:bind_keys()
    return app, ue, pc, function(i) hovered = i end, function() return loops end
  end

  it("opening and closing sets and restores cursor and input mode", function()
    local _, ue, pc = mouse_app(true)
    ue.key_binds.F3()
    assert.is_true(pc.bShowMouseCursor)
    ue.key_binds.F3()
    assert.is_false(pc.bShowMouseCursor)
    assert.same({ "UIOnly", "GameOnly" }, pc.modes)
  end)

  it("ESCAPE and root-level back close the menu and release the mouse", function()
    local app, ue, pc = mouse_app(true)
    ue.key_binds.F3()
    ue.key_binds.ESCAPE()
    assert.is_false(app.menu:is_open())
    assert.is_false(pc.bShowMouseCursor)
    ue.key_binds.F3()
    ue.key_binds.RIGHT_MOUSE_BUTTON()   -- back at root closes
    assert.is_false(app.menu:is_open())
    assert.same({ "UIOnly", "GameOnly", "UIOnly", "GameOnly" }, pc.modes)
  end)

  it("mouse handlers are no-ops while closed", function()
    local app, ue, pc, set_hover = mouse_app(true)
    set_hover(1)
    ue.key_binds.LEFT_MOUSE_BUTTON()
    ue.key_binds.RIGHT_MOUSE_BUTTON()
    ue.key_binds.ESCAPE()
    assert.is_false(app.menu:is_open())
    assert.same({}, pc.modes)
  end)

  it("left click selects the hovered row; ignored over no row", function()
    local app, ue, _, set_hover = mouse_app(true)
    ue.key_binds.F3()
    set_hover(nil)
    ue.key_binds.LEFT_MOUSE_BUTTON()
    assert.equal("RV Admin", app.menu:view().title)
    set_hover(1)                         -- first row: Teleport ...
    ue.key_binds.LEFT_MOUSE_BUTTON()
    assert.equal("Teleport", app.menu:view().title)
    set_hover(1)                         -- Me to RV
    ue.key_binds.LEFT_MOUSE_BUTTON()
    assert.equal("Teleported to RV", app.menu:view().message)
  end)

  it("hover moves the selection without a click and starts one loop", function()
    local app, ue, _, set_hover, loops = mouse_app(true)
    ue.key_binds.F3()
    set_hover(3)
    app:hover(3)
    local selected
    for i, r in ipairs(app.menu:view().rows) do if r.selected then selected = i end end
    assert.equal(3, selected)
    assert.equal(1, loops())
  end)

  it("Mouse=false binds no mouse keys and leaves cursor and input mode alone", function()
    local app, ue, pc = mouse_app(false)
    assert.is_nil(ue.key_binds.LEFT_MOUSE_BUTTON)
    assert.is_nil(ue.key_binds.RIGHT_MOUSE_BUTTON)
    assert.is_nil(ue.key_binds.ESCAPE)
    ue.key_binds.F3()
    assert.is_true(app.menu:is_open())
    assert.is_false(pc.bShowMouseCursor)
    assert.same({}, pc.modes)
  end)
end)
