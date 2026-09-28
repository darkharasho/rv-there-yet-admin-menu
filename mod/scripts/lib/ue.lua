-- The engine adapter seam: every later task talks to UE4SS only through here.
-- Every method is pcall-guarded; a UE4SS/game update degrades the mod to
-- "fewer features + a logged warning", never a crash.
local M = {}

-- UNVERIFIED PENDING RECON: docs/game-objects.md (Task 2) has not been written
-- yet because it needs a live 2-player Windows session. These are the
-- standard UE PlayerController names we assume for mouse plumbing. Once
-- recon lands, correct them here in one place.
local ASSUMED = {
  mouse_position_fn = "GetMousePosition",   -- PlayerController function -> x, y
  mouse_down_fn = "IsInputKeyDown",         -- PlayerController function(key_name) -> boolean
  left_mouse_key = "LeftMouseButton",
  cursor_visible_prop = "bShowMouseCursor",
}

local Adapter = {}
Adapter.__index = Adapter

local function get_global(name)
  local v = rawget(_G, name)
  if type(v) == "function" then return v end
  return nil
end

local function warn(self, msg)
  if self.logger then self.logger:warn(msg) end
end

function Adapter:available()
  return get_global("FindAllOf") ~= nil
end

function Adapter:find_all(class_name)
  local fn = get_global("FindAllOf")
  if not fn then return {} end
  local ok, list = pcall(fn, class_name)
  if not ok then
    warn(self, string.format("FindAllOf(%s) failed: %s", tostring(class_name), tostring(list)))
    return {}
  end
  if type(list) ~= "table" then
    warn(self, string.format("FindAllOf(%s) returned a non-table", tostring(class_name)))
    return {}
  end
  return list
end

function Adapter:find_first(class_name)
  local fn = get_global("FindFirstOf")
  if not fn then return nil end
  local ok, obj = pcall(fn, class_name)
  if not ok then
    warn(self, string.format("FindFirstOf(%s) failed: %s", tostring(class_name), tostring(obj)))
    return nil, tostring(obj)
  end
  return obj
end

function Adapter:get(obj, prop)
  if obj == nil then return nil, "cannot get property of a nil object" end
  local ok, value = pcall(function() return obj[prop] end)
  if not ok then
    warn(self, string.format("get(%s) failed: %s", tostring(prop), tostring(value)))
    return nil, tostring(value)
  end
  return value, nil
end

function Adapter:set(obj, prop, value)
  if obj == nil then return false, "cannot set property of a nil object" end
  local ok, err = pcall(function() obj[prop] = value end)
  if not ok then
    warn(self, string.format("set(%s) failed to write: %s", tostring(prop), tostring(err)))
    return false, tostring(err)
  end
  local ok2, readback = pcall(function() return obj[prop] end)
  if not ok2 then
    warn(self, string.format("set(%s) failed to read back: %s", tostring(prop), tostring(readback)))
    return false, tostring(readback)
  end
  if readback ~= value then
    local msg = string.format("write to %s did not stick", tostring(prop))
    warn(self, msg)
    return false, msg
  end
  return true, nil
end

function Adapter:call(obj, fn_name, ...)
  if obj == nil then return nil, "cannot call a method on a nil object" end
  local args = { ... }
  local n = select("#", ...)
  local ok_fn, fn = pcall(function() return obj[fn_name] end)
  if not ok_fn then
    warn(self, string.format("call(%s) failed to look up function: %s", tostring(fn_name), tostring(fn)))
    return nil, tostring(fn)
  end
  if type(fn) ~= "function" then
    local msg = string.format("no such function: %s", tostring(fn_name))
    warn(self, msg)
    return nil, msg
  end
  local ok, result = pcall(fn, obj, table.unpack(args, 1, n))
  if not ok then
    warn(self, string.format("call(%s) failed: %s", tostring(fn_name), tostring(result)))
    return nil, tostring(result)
  end
  return result, nil
end

function Adapter:is_valid(obj)
  local fn = get_global("IsValid")
  if fn then
    local ok, v = pcall(fn, obj)
    if ok then return v == true end
    warn(self, string.format("IsValid() failed: %s", tostring(v)))
    return false
  end
  return obj ~= nil
end

function Adapter:class_of(obj)
  if obj == nil then return "" end
  local ok, result = pcall(function()
    return obj:GetClass():GetFName():ToString()
  end)
  if ok and type(result) == "string" then
    return result
  end
  return ""
end

function Adapter:in_game_thread(fn)
  if type(fn) ~= "function" then return end
  local exec = get_global("ExecuteInGameThread")
  if exec then
    local ok, err = pcall(exec, fn)
    if not ok then
      warn(self, string.format("in_game_thread failed: %s", tostring(err)))
    end
    return
  end
  local ok, err = pcall(fn)
  if not ok then
    warn(self, string.format("in_game_thread failed: %s", tostring(err)))
  end
end

function Adapter:bind_key(key_name, fn)
  local reg = get_global("RegisterKeyBind")
  if not reg or type(fn) ~= "function" then return false end
  local keys = rawget(_G, "Key")
  local key = (type(keys) == "table" and keys[key_name]) or key_name
  local ok, err = pcall(reg, key, fn)
  if not ok then
    warn(self, string.format("bind_key(%s) failed: %s", tostring(key_name), tostring(err)))
    return false
  end
  return true
end

function Adapter:on_hook(signature, fn)
  local reg = get_global("RegisterHook")
  if not reg or type(fn) ~= "function" then return false end
  local ok, err = pcall(reg, signature, fn)
  if not ok then
    warn(self, string.format("on_hook(%s) failed: %s", tostring(signature), tostring(err)))
    return false
  end
  return true
end

-- Returns nil (never a partial table) unless the controller and every
-- function it needs are present and well-behaved.
function Adapter:mouse_state()
  local pc = self:find_first("PlayerController")
  if pc == nil then return nil end

  local ok_pos_fn, pos_fn = pcall(function() return pc[ASSUMED.mouse_position_fn] end)
  if not ok_pos_fn or type(pos_fn) ~= "function" then return nil end
  local ok_pos, x, y = pcall(pos_fn, pc)
  if not ok_pos or type(x) ~= "number" or type(y) ~= "number" then return nil end

  local ok_down_fn, down_fn = pcall(function() return pc[ASSUMED.mouse_down_fn] end)
  if not ok_down_fn or type(down_fn) ~= "function" then return nil end
  local ok_down, down = pcall(down_fn, pc, ASSUMED.left_mouse_key)
  if not ok_down or type(down) ~= "boolean" then return nil end

  return { x = x, y = y, down = down }
end

-- Returns the PREVIOUS value of bShowMouseCursor, or nil if the write failed.
function Adapter:set_cursor_visible(visible)
  local pc = self:find_first("PlayerController")
  if pc == nil then return nil end

  local ok_prev, prev = pcall(function() return pc[ASSUMED.cursor_visible_prop] end)
  if not ok_prev then return nil end

  local ok_set, err = pcall(function() pc[ASSUMED.cursor_visible_prop] = visible end)
  if not ok_set then
    warn(self, string.format("set_cursor_visible failed: %s", tostring(err)))
    return nil
  end

  return prev
end

function M.new(logger)
  return setmetatable({ logger = logger }, Adapter)
end

return M
