-- Test double for mod/scripts/lib/ue.lua. Implements the same method
-- surface over plain Lua tables so later tasks (menu, renderer, player
-- actions) can inject it instead of the real adapter in headless tests.
local Fake = {}
Fake.__index = Fake

local M = {}

function M.new()
  return setmetatable({
    objects = {},        -- fake.objects[class_name] = { obj1, obj2, ... }
    calls = {},           -- append-only log of { op = ..., ... } for assertions
    fail_on = {},          -- fail_on["set:Health"] = true simulates a rejected write
    hooks = {},
    key_binds = {},
    mouse = { x = 0, y = 0, down = false },
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

function Fake:call(obj, fn_name, ...)
  log(self, { op = "call", fn_name = fn_name, args = { ... } })
  if obj == nil then return nil, "cannot call a method on a nil object" end
  if self.fail_on["call:" .. tostring(fn_name)] then
    return nil, string.format("call to %s rejected", tostring(fn_name))
  end
  local fn = obj[fn_name]
  if type(fn) ~= "function" then
    return nil, string.format("no such function: %s", tostring(fn_name))
  end
  return fn(obj, ...)
end

function Fake:is_valid(obj)
  return obj ~= nil
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
  return { x = self.mouse.x, y = self.mouse.y, down = self.mouse.down }
end

function Fake:set_cursor_visible(visible)
  local prev = self.cursor_visible
  self.cursor_visible = visible
  return prev
end

return M
