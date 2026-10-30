package.path = "mod/scripts/?.lua;" .. package.path
local mouse_mod = require("lib.mouse")
local fake_ue = require("tests.support.fake_ue")

local function make(opts)
  opts = opts or {}
  local ue = fake_ue.new()
  local pc = { bShowMouseCursor = false, bEnableClickEvents = false, ignore_calls = {}, modes = {} }
  function pc:SetIgnoreLookInput(v) self.ignore_calls[#self.ignore_calls + 1] = v end
  local lib = {}
  function lib:SetInputMode_UIOnlyEx(p, w, lock, flush)
    if opts.ui_only_fails then error("boom") end
    p.modes[#p.modes + 1] = { "UIOnlyEx", w, lock, flush }
  end
  function lib:SetInputMode_GameAndUIEx(p, w, lock, hide, flush)
    p.modes[#p.modes + 1] = { "GameAndUIEx", w, lock, hide, flush }
  end
  function lib:SetInputMode_GameOnly(p, flush) p.modes[#p.modes + 1] = { "GameOnly", flush } end
  local loops = {}
  local env = {
    StaticFindObject = function(path) if path == "/Script/UMG.Default__WidgetBlueprintLibrary" then return lib end end,
    LoopAsync = function(ms, fn) loops[#loops + 1] = { ms = ms, fn = fn, done = false } end,
  }
  local widget = {}
  local hovered
  local overlay = { widget_object = function() return widget end, hovered_index = function() return hovered end }
  local hovers = {}
  local m = mouse_mod.new({
    ue = ue, overlay = overlay, env = env, get_pc = function() return pc end,
    on_hover = function(i) hovers[#hovers + 1] = i end,
  })
  local function tick()
    for _, l in ipairs(loops) do
      if not l.done and l.fn() == true then l.done = true end
    end
  end
  local function alive()
    local n = 0
    for _, l in ipairs(loops) do if not l.done then n = n + 1 end end
    return n
  end
  return {
    m = m, pc = pc, widget = widget, loops = loops, hovers = hovers, tick = tick, alive = alive,
    set_hover = function(i) hovered = i end,
  }
end

describe("mouse mode", function()
  it("shows the cursor, sets UI-only input and restores everything on leave", function()
    local t = make()
    t.pc.bShowMouseCursor = false
    t.m:enter()
    assert.is_true(t.pc.bShowMouseCursor)
    assert.is_true(t.pc.bEnableClickEvents)
    assert.same({ "UIOnlyEx", t.widget, 0, false }, t.pc.modes[1])
    assert.equal(50, t.loops[1].ms)
    t.m:leave()
    assert.is_false(t.pc.bShowMouseCursor)
    assert.same({ "GameOnly", false }, t.pc.modes[#t.pc.modes])
    assert.same({}, t.pc.ignore_calls)
  end)

  it("restores a cursor that was already visible", function()
    local t = make()
    t.pc.bShowMouseCursor = true
    t.m:enter()
    t.m:leave()
    assert.is_true(t.pc.bShowMouseCursor)
  end)

  it("falls back to GameAndUI and balances SetIgnoreLookInput exactly once", function()
    local t = make({ ui_only_fails = true })
    t.m:enter()
    assert.equal("GameAndUIEx", t.pc.modes[1][1])
    assert.same({ true }, t.pc.ignore_calls)
    t.m:leave()
    t.m:leave()
    assert.same({ true, false }, t.pc.ignore_calls)
    t.m:enter()   -- a second open/close stays balanced too
    t.m:leave()
    assert.same({ true, false, true, false }, t.pc.ignore_calls)
  end)

  it("never touches look input when UI-only works", function()
    local t = make()
    t.m:enter(); t.m:leave()
    assert.same({}, t.pc.ignore_calls)
  end)

  it("enter is idempotent and starts only one hover loop", function()
    local t = make()
    t.m:enter(); t.m:enter()
    assert.equal(1, #t.loops)
    t.m:leave()
    t.m:enter()                       -- reopened before the old loop ticked out
    assert.equal(1, #t.loops)
    assert.equal(1, t.alive())
    t.m:leave()
    t.tick()
    assert.equal(0, t.alive())
    t.m:enter()                       -- now a fresh loop is allowed
    assert.equal(2, #t.loops)
    assert.equal(1, t.alive())
  end)

  it("the loop stops itself after leave", function()
    local t = make()
    t.m:enter()
    t.tick()
    assert.equal(1, t.alive())
    t.m:leave()
    t.tick()
    assert.equal(0, t.alive())
  end)

  it("reports a hovered row only when it changes", function()
    local t = make()
    t.m:enter()
    t.set_hover(2); t.tick(); t.tick()
    t.set_hover(nil); t.tick()
    t.set_hover(3); t.tick()
    assert.same({ 2, 3 }, t.hovers)
  end)

  it("stays keyboard-only without a widget or without LoopAsync", function()
    local t = make()
    t.m.overlay.widget_object = function() return nil end
    t.m:enter()
    assert.is_false(t.pc.bShowMouseCursor)
    assert.equal(0, #t.loops)

    local t2 = make()
    t2.m.env.LoopAsync = nil
    t2.m:enter()
    assert.is_true(t2.pc.bShowMouseCursor)
    t2.m:leave()
  end)
end)
