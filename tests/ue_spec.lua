local ue = require("mod.scripts.lib.ue")
local log = require("mod.scripts.lib.log")
local fake_ue = require("tests.support.fake_ue")

local UE_GLOBALS = {
  "FindAllOf", "FindFirstOf", "ExecuteInGameThread",
  "RegisterKeyBind", "RegisterHook", "IsValid", "Key",
}

local function quiet(collected)
  return log.new{ name = "T", level = "DEBUG", sink = function(s) collected[#collected+1] = s end }
end

describe("ue adapter", function()
  local saved

  before_each(function()
    saved = {}
    for _, name in ipairs(UE_GLOBALS) do
      saved[name] = rawget(_G, name)
      _G[name] = nil
    end
  end)

  after_each(function()
    for _, name in ipairs(UE_GLOBALS) do
      _G[name] = saved[name]
    end
  end)

  it("returns an empty table when FindAllOf is absent", function()
    local a = ue.new(quiet({}))          -- no UE4SS globals in _G
    assert.same({}, a:find_all("Pawn"))
    assert.is_false(a:available())
  end)

  it("reports a write that does not stick", function()
    _G.FindAllOf = function() return {} end
    local obj = setmetatable({}, { __newindex = function() end, __index = function() return 5 end })
    local a = ue.new(quiet({}))
    local ok, err = a:set(obj, "Health", 100)
    assert.is_false(ok)
    assert.truthy(err:find("did not stick"))
  end)

  it("never propagates an engine error", function()
    local obj = setmetatable({}, { __index = function() error("engine exploded") end })
    local a = ue.new(quiet({}))
    local v, err = a:get(obj, "Health")
    assert.is_nil(v)
    assert.truthy(err)
  end)

  it("reports available() true when FindAllOf is a function", function()
    _G.FindAllOf = function() return {} end
    local a = ue.new(quiet({}))
    assert.is_true(a:available())
  end)

  it("finds nothing and warns when FindAllOf returns a non-table", function()
    _G.FindAllOf = function() return "not a table" end
    local lines = {}
    local a = ue.new(quiet(lines))
    assert.same({}, a:find_all("Pawn"))
    assert.truthy(table.concat(lines):find("WARN"))
  end)

  it("returns nil from find_first when FindFirstOf is absent", function()
    local a = ue.new(quiet({}))
    assert.is_nil(a:find_first("Pawn"))
  end)

  it("returns the object FindFirstOf produces", function()
    local pawn = { name = "pawn" }
    _G.FindFirstOf = function() return pawn end
    local a = ue.new(quiet({}))
    assert.equal(pawn, a:find_first("Pawn"))
  end)

  it("returns nil and an error from find_first when the engine call errors", function()
    _G.FindFirstOf = function() error("boom") end
    local a = ue.new(quiet({}))
    local obj, err = a:find_first("Pawn")
    assert.is_nil(obj)
    assert.truthy(err)
  end)

  it("gets a plain property successfully", function()
    local obj = { Health = 42 }
    local a = ue.new(quiet({}))
    local v, err = a:get(obj, "Health")
    assert.equal(42, v)
    assert.is_nil(err)
  end)

  it("errors get() on a nil object without crashing", function()
    local a = ue.new(quiet({}))
    local v, err = a:get(nil, "Health")
    assert.is_nil(v)
    assert.truthy(err)
  end)

  it("sets a property that sticks", function()
    local obj = { Health = 0 }
    local a = ue.new(quiet({}))
    local ok, err = a:set(obj, "Health", 100)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(100, obj.Health)
  end)

  it("reports a write error without crashing when the write itself throws", function()
    local obj = setmetatable({}, { __newindex = function() error("write exploded") end })
    local a = ue.new(quiet({}))
    local ok, err = a:set(obj, "Health", 100)
    assert.is_false(ok)
    assert.truthy(err)
  end)

  it("calls a method on the object and returns ok plus its result", function()
    local obj = { Ping = function(self, n) return n + 1 end }
    local a = ue.new(quiet({}))
    local ok, v = a:call(obj, "Ping", 41)
    assert.is_true(ok)
    assert.equal(42, v)
  end)

  it("call() carries EVERY return value, not just the first", function()
    -- The teleport case: K2_GetActorLocation returns x, y, z. A call seam
    -- that drops y and z writes garbage into the game.
    local obj = { GetLocation = function() return 1, 2, 3 end }
    local a = ue.new(quiet({}))
    local ok, x, y, z = a:call(obj, "GetLocation")
    assert.is_true(ok)
    assert.same({ 1, 2, 3 }, { x, y, z })
  end)

  it("call() carries a nil in the middle of the return values", function()
    local obj = { Tri = function() return 1, nil, 3 end }
    local a = ue.new(quiet({}))
    local res = table.pack(a:call(obj, "Tri"))
    assert.equal(4, res.n)
    assert.is_true(res[1])
    assert.is_nil(res[3])
    assert.equal(3, res[4])
  end)

  it("call() passes every argument through", function()
    local obj = { Sum = function(self, a, b, c) return (a or 0) + (b or 0) + (c or 0) end }
    local a = ue.new(quiet({}))
    local ok, sum = a:call(obj, "Sum", 1, 2, 3)
    assert.is_true(ok)
    assert.equal(6, sum)
  end)

  it("never propagates an error from call()", function()
    local obj = { Boom = function() error("kaboom") end }
    local a = ue.new(quiet({}))
    local ok, err = a:call(obj, "Boom")
    assert.is_false(ok)
    assert.truthy(err)
  end)

  it("reports an error from call() when the function does not exist", function()
    local obj = {}
    local a = ue.new(quiet({}))
    local ok, err = a:call(obj, "NoSuchFn")
    assert.is_false(ok)
    assert.truthy(err:find("no such function"))
  end)

  it("reports an error from call() on a nil object", function()
    local a = ue.new(quiet({}))
    local ok, err = a:call(nil, "Anything")
    assert.is_false(ok)
    assert.truthy(err)
  end)

  it("reports an error from call() when looking up the function throws", function()
    local obj = setmetatable({}, { __index = function() error("lookup exploded") end })
    local a = ue.new(quiet({}))
    local ok, err = a:call(obj, "Whatever")
    assert.is_false(ok)
    assert.truthy(err)
  end)

  it("call() warns on failure and call_quiet() does not", function()
    local obj = { Boom = function() error("kaboom") end }
    local loud, silent = {}, {}
    assert.is_false(ue.new(quiet(loud)):call(obj, "Boom"))
    assert.is_false(ue.new(quiet(silent)):call_quiet(obj, "Boom"))
    assert.truthy(table.concat(loud):find("WARN"))
    assert.equal(0, #silent)
  end)

  it("call_quiet() carries the same values as call()", function()
    local obj = { GetLocation = function() return 1, 2, 3 end }
    local a = ue.new(quiet({}))
    assert.same({ true, 1, 2, 3 }, { a:call_quiet(obj, "GetLocation") })
  end)

  it("is_valid is false for nil and true for a plain object without an engine IsValid global", function()
    local a = ue.new(quiet({}))
    assert.is_false(a:is_valid(nil))
    assert.is_true(a:is_valid({}))
  end)

  it("is_valid defers to the engine IsValid global when present", function()
    _G.IsValid = function() return false end
    local a = ue.new(quiet({}))
    assert.is_false(a:is_valid({}))
  end)

  it("class_of returns an empty string when GetClass is unavailable", function()
    local a = ue.new(quiet({}))
    assert.equal("", a:class_of({}))
  end)

  it("class_of never crashes on an object without GetClass", function()
    local obj = setmetatable({}, { __index = function() error("no class") end })
    local a = ue.new(quiet({}))
    assert.equal("", a:class_of(obj))
  end)

  it("in_game_thread calls the function directly when ExecuteInGameThread is absent", function()
    local called = false
    local a = ue.new(quiet({}))
    a:in_game_thread(function() called = true end)
    assert.is_true(called)
  end)

  it("in_game_thread routes through ExecuteInGameThread when present", function()
    local routed = false
    _G.ExecuteInGameThread = function(fn) routed = true; fn() end
    local called = false
    local a = ue.new(quiet({}))
    a:in_game_thread(function() called = true end)
    assert.is_true(routed)
    assert.is_true(called)
  end)

  it("in_game_thread never crashes when the callback errors", function()
    _G.ExecuteInGameThread = function(fn) fn() end
    local a = ue.new(quiet({}))
    a:in_game_thread(function() error("thread boom") end)
  end)

  it("bind_key returns false when RegisterKeyBind is absent", function()
    local a = ue.new(quiet({}))
    assert.is_false(a:bind_key("F3", function() end))
  end)

  it("bind_key returns true when RegisterKeyBind accepts the binding", function()
    _G.RegisterKeyBind = function() end
    local a = ue.new(quiet({}))
    assert.is_true(a:bind_key("F3", function() end))
  end)

  it("bind_key resolves the key name through the Key table before registering", function()
    _G.Key = { F3 = 42 }
    local recorded = {}
    _G.RegisterKeyBind = function(key, fn)
      recorded.key = key
      recorded.fn = fn
    end
    local callback = function() end
    local a = ue.new(quiet({}))
    assert.is_true(a:bind_key("F3", callback))
    assert.equal(42, recorded.key)
    assert.equal(callback, recorded.fn)
  end)

  it("bind_key fails loudly when the Key table lacks the name", function()
    _G.Key = { F3 = 42 }
    local registered = false
    _G.RegisterKeyBind = function() registered = true end
    local lines = {}
    local a = ue.new(quiet(lines))
    assert.is_false(a:bind_key("PAGE_UP", function() end))
    assert.is_false(registered)                 -- never hands a raw string to UE4SS
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("PAGE_UP"))
  end)

  it("on_hook returns false when RegisterHook is absent", function()
    local a = ue.new(quiet({}))
    assert.is_false(a:on_hook("/Script/Engine.HUD:ReceiveDrawHUD", function() end))
  end)

  it("on_hook returns true when RegisterHook accepts the hook", function()
    _G.RegisterHook = function() end
    local a = ue.new(quiet({}))
    assert.is_true(a:on_hook("/Script/Engine.HUD:ReceiveDrawHUD", function() end))
  end)

  it("mouse_state is nil when FindFirstOf is absent", function()
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state is nil when the controller is missing the mouse position function", function()
    _G.FindFirstOf = function() return {} end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state returns position and button state when everything is available", function()
    local pc = {
      GetMousePosition = function() return 12, 34 end,
      IsInputKeyDown = function(self, key) return key == "LeftMouseButton" end,
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    local state = a:mouse_state()
    assert.same({ x = 12, y = 34, down = true }, state)
  end)

  it("mouse_state is nil, not partial, when the mouse position call errors", function()
    local pc = {
      GetMousePosition = function() error("no cursor") end,
      IsInputKeyDown = function() return false end,
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state is nil, not partial, when the down-button function is missing", function()
    local pc = {
      GetMousePosition = function() return 12, 34 end,
      -- IsInputKeyDown intentionally absent
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state is nil, not partial, when the down-button field is not a function", function()
    local pc = {
      GetMousePosition = function() return 12, 34 end,
      IsInputKeyDown = "not a function",
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state is nil, not partial, when the down-button call errors", function()
    local pc = {
      GetMousePosition = function() return 12, 34 end,
      IsInputKeyDown = function() error("input system unavailable") end,
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("mouse_state is nil, not partial, when the down-button call returns a non-boolean", function()
    local pc = {
      GetMousePosition = function() return 12, 34 end,
      IsInputKeyDown = function() return "yes" end,
    }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:mouse_state())
  end)

  it("set_cursor_visible is nil when the controller is unavailable", function()
    local a = ue.new(quiet({}))
    assert.is_nil(a:set_cursor_visible(true))
  end)

  it("set_cursor_visible writes the new value and returns the previous one", function()
    local pc = { bShowMouseCursor = false }
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    local prev = a:set_cursor_visible(true)
    assert.is_false(prev)
    assert.is_true(pc.bShowMouseCursor)
  end)

  it("set_cursor_visible is nil when the write throws", function()
    local pc = setmetatable({}, {
      __index = function() return false end,
      __newindex = function() error("locked") end,
    })
    _G.FindFirstOf = function() return pc end
    local a = ue.new(quiet({}))
    assert.is_nil(a:set_cursor_visible(true))
  end)
end)

describe("fake_ue", function()
  it("fail_on makes set() return false", function()
    local fake = fake_ue.new()
    local obj = { Health = 0 }
    fake.fail_on["set:Health"] = true
    local ok, err = fake:set(obj, "Health", 100)
    assert.is_false(ok)
    assert.truthy(err)
    assert.equal(0, obj.Health)
  end)

  it("find_all on an unknown class returns an empty table", function()
    local fake = fake_ue.new()
    assert.same({}, fake:find_all("SomeUnregisteredClass"))
  end)

  it("find_all returns the seeded objects and logs the call", function()
    local fake = fake_ue.new()
    local list = { { name = "a" }, { name = "b" } }
    fake.objects["Pawn"] = list
    assert.equal(list, fake:find_all("Pawn"))
    assert.equal("find_all", fake.calls[#fake.calls].op)
  end)

  it("set() without fail_on writes the value through", function()
    local fake = fake_ue.new()
    local obj = { Health = 0 }
    local ok, err = fake:set(obj, "Health", 100)
    assert.is_true(ok)
    assert.is_nil(err)
    assert.equal(100, obj.Health)
  end)

  it("mouse_state and set_cursor_visible are driven by plain fields", function()
    local fake = fake_ue.new()
    fake.mouse.x, fake.mouse.y, fake.mouse.down = 5, 6, true
    assert.same({ x = 5, y = 6, down = true }, fake:mouse_state())

    local prev = fake:set_cursor_visible(false)
    assert.is_true(prev)
    assert.is_false(fake.cursor_visible)
  end)

  it("call() returns ok plus every return value, like the real adapter", function()
    local fake = fake_ue.new()
    local obj = { GetLocation = function() return 1, 2, 3 end }
    assert.same({ true, 1, 2, 3 }, { fake:call(obj, "GetLocation") })
    assert.same({ true, 1, 2, 3 }, { fake:call_quiet(obj, "GetLocation") })
  end)

  it("call() failure shapes match the real adapter's", function()
    local fake = fake_ue.new()
    local real = ue.new(quiet({}))

    local ok1, err1 = fake:call(nil, "Anything")
    local rok1, rerr1 = real:call(nil, "Anything")
    assert.is_false(ok1); assert.is_false(rok1)
    assert.equal(rerr1, err1)

    local ok2, err2 = fake:call({}, "NoSuchFn")
    local rok2, rerr2 = real:call({}, "NoSuchFn")
    assert.is_false(ok2); assert.is_false(rok2)
    assert.equal(rerr2, err2)

    local boom = { Boom = function() error("kaboom") end }
    local ok3, err3 = fake:call(boom, "Boom")
    local rok3 = real:call(boom, "Boom")
    assert.is_false(ok3); assert.is_false(rok3)
    assert.truthy(err3:find("kaboom"))

    fake.fail_on["call:Kill"] = true
    local ok4, err4 = fake:call({ Kill = function() end }, "Kill")
    assert.is_false(ok4)
    assert.truthy(err4)
  end)

  it("invalid[obj] reproduces the real adapter's destroyed-object shape", function()
    local fake = fake_ue.new()
    local pawn = { name = "pawn" }
    assert.is_true(fake:is_valid(pawn))
    fake.invalid[pawn] = true
    assert.is_false(fake:is_valid(pawn))
    assert.is_false(fake:is_valid(nil))

    -- Real adapter, same shape: IsValid present and returning false.
    _G.IsValid = function() return false end
    local real = ue.new(quiet({}))
    assert.is_false(real:is_valid(pawn))
    _G.IsValid = nil
  end)

  it("mouse = nil reproduces the real adapter's no-mouse-plumbing nil", function()
    local fake = fake_ue.new()
    fake.mouse = nil
    assert.is_nil(fake:mouse_state())
    assert.is_nil(ue.new(quiet({})):mouse_state())   -- no FindFirstOf global
  end)

  it("fail_on set_cursor_visible reproduces the real adapter's nil", function()
    local fake = fake_ue.new()
    fake.fail_on["set_cursor_visible"] = true
    assert.is_nil(fake:set_cursor_visible(false))
    assert.is_true(fake.cursor_visible)             -- the write did not happen

    local pc = setmetatable({}, {
      __index = function() return false end,
      __newindex = function() error("locked") end,
    })
    _G.FindFirstOf = function() return pc end
    assert.is_nil(ue.new(quiet({})):set_cursor_visible(true))
    _G.FindFirstOf = nil
  end)

  it("fail_on find_first reproduces the real adapter's nil, err pair", function()
    local fake = fake_ue.new()
    fake.objects["Pawn"] = { { name = "pawn" } }
    fake.fail_on["find_first:Pawn"] = true
    local obj, err = fake:find_first("Pawn")
    assert.is_nil(obj)
    assert.truthy(err)

    _G.FindFirstOf = function() error("boom") end
    local robj, rerr = ue.new(quiet({})):find_first("Pawn")
    assert.is_nil(robj)
    assert.truthy(rerr)
    _G.FindFirstOf = nil
  end)
end)
