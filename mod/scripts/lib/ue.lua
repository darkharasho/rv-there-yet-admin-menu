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

-- `quiet` suppresses the warning for callers polled every frame; the return
-- shape is identical either way.
local function find_first_impl(self, class_name, quiet)
  local fn = get_global("FindFirstOf")
  if not fn then return nil end
  local ok, obj = pcall(fn, class_name)
  if not ok then
    if not quiet then
      warn(self, string.format("FindFirstOf(%s) failed: %s", tostring(class_name), tostring(obj)))
    end
    return nil, tostring(obj)
  end
  return obj
end

function Adapter:find_first(class_name)
  return find_first_impl(self, class_name, false)
end

function Adapter:get(obj, prop)
  -- A nil object here is a caller programming error, not malformed user
  -- input, so this degrades silently (no warn) rather than spamming the
  -- log from ordinary guard code. Same reasoning applies to the nil-object
  -- guards in set/call/class_of below.
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

-- CALL CONTRACT (implemented identically in tests/support/fake_ue.lua):
--
--   local ok, a, b, c = adapter:call(obj, "Fn", arg1)
--
--   success -> true, <EVERY value the engine function returned>
--   failure -> false, <error message string>
--
-- ALWAYS branch on the first value. `local v, err = adapter:call(...)` is
-- WRONG under this contract: it reads the ok flag as the value and the
-- function's first real return value as an error. Carrying all returns is
-- what makes multi-value engine functions (K2_GetActorLocation -> x, y, z)
-- usable through this seam at all.
local function invoke(self, obj, fn_name, ...)
  if obj == nil then return false, "cannot call a method on a nil object" end
  local args = { ... }
  local n = select("#", ...)
  local ok_fn, fn = pcall(function() return obj[fn_name] end)
  if not ok_fn then return false, tostring(fn) end
  if type(fn) ~= "function" then
    return false, string.format("no such function: %s", tostring(fn_name))
  end
  local res = table.pack(pcall(fn, obj, table.unpack(args, 1, n)))
  if not res[1] then return false, tostring(res[2]) end
  -- res[1] is pcall's true, which is also the contract's ok flag.
  return table.unpack(res, 1, res.n)
end

function Adapter:call(obj, fn_name, ...)
  local res = table.pack(invoke(self, obj, fn_name, ...))
  if not res[1] then
    warn(self, string.format("call(%s) failed: %s", tostring(fn_name), tostring(res[2])))
  end
  return table.unpack(res, 1, res.n)
end

-- Same contract as call(), but silent. For per-frame callers only: a
-- permanent failure (a renamed engine function) would otherwise write one
-- warning to UE4SS.log every single frame and grow the log without bound.
function Adapter:call_quiet(obj, fn_name, ...)
  return invoke(self, obj, fn_name, ...)
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
  local key = key_name
  if type(keys) == "table" then
    -- When UE4SS's Key table exists it is authoritative. Passing an
    -- unknown name through as a raw string registers a bind that silently
    -- never fires, so fail loudly instead and name the key.
    -- Spellings are UNVERIFIED: docs/game-objects.md question 10.
    if keys[key_name] == nil then
      warn(self, string.format(
        "bind_key(%s) failed: UE4SS's Key table has no such key name; the hotkey is not bound",
        tostring(key_name)))
      return false
    end
    key = keys[key_name]
  end
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
-- function it needs are present and well-behaved. Goes through call_quiet
-- rather than call because a HUD hook polls this every frame.
function Adapter:mouse_state()
  -- Quiet lookup too: a throwing FindFirstOf would otherwise warn every frame,
  -- which is the exact log flood call_quiet exists to avoid.
  local pc = find_first_impl(self, "PlayerController", true)
  if pc == nil then return nil end

  local ok_pos, x, y = self:call_quiet(pc, ASSUMED.mouse_position_fn)
  if not ok_pos or type(x) ~= "number" or type(y) ~= "number" then return nil end

  local ok_down, down = self:call_quiet(pc, ASSUMED.mouse_down_fn, ASSUMED.left_mouse_key)
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
