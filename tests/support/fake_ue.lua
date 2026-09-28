-- Test double for mod/scripts/lib/ue.lua. Implements the same method
-- surface over plain Lua tables so later tasks (menu, renderer, player
-- actions) can inject it instead of the real adapter in headless tests.
--
-- Every failure the real adapter can produce must be reachable here, in
-- the real adapter's exact failure shape, or a test written against this
-- fake proves nothing about the live game. The knobs:
--   fake.fail_on["get:Prop"]            -> get() returns nil, err
--   fake.fail_on["set:Prop"]            -> set() returns false, err
--   fake.fail_on["call:Fn"]             -> call() returns false, err
--   fake.fail_on["find_first:Class"]    -> find_first() returns nil, err
--   fake.fail_on["set_cursor_visible"]  -> set_cursor_visible() returns nil
--   fake.invalid[obj] = true            -> is_valid(obj) is false
--   fake.mouse = nil                    -> mouse_state() returns nil
local Fake = {}
Fake.__index = Fake

local M = {}

function M.new()
  return setmetatable({
    objects = {},        -- fake.objects[class_name] = { obj1, obj2, ... }
    calls = {},           -- append-only log of { op = ..., ... } for assertions
    fail_on = {},          -- fail_on["set:Health"] = true simulates a rejected write
    invalid = {},          -- invalid[obj] = true simulates a destroyed UObject
    hooks = {},
    key_binds = {},
    mouse = { x = 0, y = 0, down = false },  -- nil simulates no mouse plumbing
    cursor_visible = true,
    available_flag = true,
  }, Fake)
end

local function log(self, entry)
  self.calls[#self.calls + 1] = entry
end

function Fake:available()
  return self.available_flag
end

function Fake:find_all(class_name)
  log(self, { op = "find_all", class_name = class_name })
  return self.objects[class_name] or {}
end

function Fake:find_first(class_name)
  log(self, { op = "find_first", class_name = class_name })
  if self.fail_on["find_first:" .. tostring(class_name)] then
    return nil, string.format("FindFirstOf(%s) failed: simulated", tostring(class_name))
  end
  local list = self.objects[class_name]
  if list and list[1] ~= nil then return list[1] end
  return nil
end

function Fake:get(obj, prop)
  log(self, { op = "get", prop = prop })
  if obj == nil then return nil, "cannot get property of a nil object" end
  if self.fail_on["get:" .. tostring(prop)] then
    return nil, string.format("get %s rejected", tostring(prop))
  end
  return obj[prop], nil
end

function Fake:set(obj, prop, value)
  log(self, { op = "set", prop = prop, value = value })
  if obj == nil then return false, "cannot set property of a nil object" end
  if self.fail_on["set:" .. tostring(prop)] then
    return false, string.format("write to %s did not stick", tostring(prop))
  end
  obj[prop] = value
  return true, nil
end

-- See the CALL CONTRACT comment in mod/scripts/lib/ue.lua: returns
-- `true, <all return values>` or `false, <error message>`. This must stay
-- byte-for-byte equivalent in shape to the real adapter's invoke().
local function invoke(self, obj, fn_name, ...)
  if obj == nil then return false, "cannot call a method on a nil object" end
  if self.fail_on["call:" .. tostring(fn_name)] then
    return false, string.format("call to %s rejected", tostring(fn_name))
  end
  local fn = obj[fn_name]
  if type(fn) ~= "function" then
    return false, string.format("no such function: %s", tostring(fn_name))
  end
  local res = table.pack(pcall(fn, obj, ...))
  if not res[1] then return false, tostring(res[2]) end
  return table.unpack(res, 1, res.n)
end

function Fake:call(obj, fn_name, ...)
  log(self, { op = "call", fn_name = fn_name, args = { ... } })
  return invoke(self, obj, fn_name, ...)
end

function Fake:call_quiet(obj, fn_name, ...)
  log(self, { op = "call_quiet", fn_name = fn_name, args = { ... } })
  return invoke(self, obj, fn_name, ...)
end

function Fake:is_valid(obj)
  if obj == nil then return false end
  return self.invalid[obj] ~= true
end

function Fake:class_of(obj)
  if type(obj) == "table" and obj.__class ~= nil then
    return obj.__class
  end
  return ""
end

function Fake:in_game_thread(fn)
  if type(fn) == "function" then fn() end
end

function Fake:bind_key(key_name, fn)
  self.key_binds[key_name] = fn
  return true
end

function Fake:on_hook(signature, fn)
  self.hooks[signature] = self.hooks[signature] or {}
  self.hooks[signature][#self.hooks[signature] + 1] = fn
  return true
end

function Fake:mouse_state()
  if self.mouse == nil then return nil end
  return { x = self.mouse.x, y = self.mouse.y, down = self.mouse.down }
end

function Fake:set_cursor_visible(visible)
  if self.fail_on["set_cursor_visible"] then return nil end
  local prev = self.cursor_visible
  self.cursor_visible = visible
  return prev
end

return M
