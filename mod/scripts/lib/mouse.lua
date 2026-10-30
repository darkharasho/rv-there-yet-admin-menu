-- Mouse support: shows the cursor and switches the controller to UI input
-- while the menu is open, and polls row hover. Everything here is a GUESS
-- until the in-game test (see CHANGELOG 0.2.0). Every engine call is
-- pcall-guarded; a failure logs once and the menu stays keyboard-only.
--
-- Engine names (CXXHeaderDump): APlayerController.bShowMouseCursor /
-- bEnableClickEvents, AController.SetIgnoreLookInput(bool),
-- UWidgetBlueprintLibrary.SetInputMode_UIOnlyEx(pc, widget, EMouseLockMode,
-- bFlushInput), SetInputMode_GameAndUIEx(pc, widget, lock, bHideCursor,
-- bFlush), SetInputMode_GameOnly(pc, bFlush), UWidget.IsHovered().
local M = {}

local LIB_PATH = "/Script/UMG.Default__WidgetBlueprintLibrary"
local DO_NOT_LOCK = 0
local POLL_MS = 50

local Mouse = {}
Mouse.__index = Mouse

-- opts: ue (adapter), logger, overlay, get_pc (-> local PlayerController),
-- on_hover (function(index), called when the hovered row changes),
-- env (global table; default _G).
function M.new(opts)
  return setmetatable({
    ue = opts.ue,
    logger = opts.logger,
    overlay = opts.overlay,
    get_pc = opts.get_pc,
    on_hover = opts.on_hover,
    env = opts.env or _G,
    active = false,       -- mouse mode currently applied
    loop_alive = false,   -- a LoopAsync callback is still scheduled
    last_hover = nil,
    pc = nil,
    prev_cursor = nil,
    ignore_look = false,
    warned = {},
  }, Mouse)
end

local function warn_once(self, key, msg)
  if self.warned[key] then return end
  self.warned[key] = true
  if self.logger then pcall(self.logger.warn, self.logger, msg) end
end

-- Plain (non-raw) lookup: UE4SS may serve some globals through _G's
-- metatable, which rawget cannot see.
local function lookup(t, name)
  local ok, v = pcall(function() return t[name] end)
  if ok then return v end
  return nil
end

-- UE4SS exposes some globals (FName, FText, ...) as callable tables or
-- userdata with a __call metamethod rather than plain functions.
local function callable(v)
  if type(v) == "function" then return true end
  local t = type(v)
  -- UE4SS FName/FText are userdata whose metatable does not expose __call
  -- to Lua (seen in game, v0.2.2), so any userdata counts as callable; the
  -- call sites are pcall-guarded.
  if t == "userdata" then return true end
  if t ~= "table" then return false end
  local ok, mt = pcall(getmetatable, v)
  return ok and type(mt) == "table" and mt.__call ~= nil
end

local function global_fn(self, name)
  local v = lookup(self.env, name)
  if callable(v) then return v end
  return nil
end

local function find_lib(self)
  local find = global_fn(self, "StaticFindObject")
  if not find then return nil end
  local ok, lib = pcall(find, LIB_PATH)
  if ok and lib ~= nil and self.ue:is_valid(lib) then return lib end
  return nil
end

-- Hover poll, run on the game thread. Only reacts when the hovered row
-- CHANGES, so a stationary mouse cannot undo keyboard navigation.
function Mouse:poll()
  if not self.active then return end
  local idx = self.overlay:hovered_index()
  if idx ~= nil and idx ~= self.last_hover and self.on_hover then
    self.on_hover(idx)
  end
  self.last_hover = idx
end

-- Marks the current hover as already handled (call after keyboard input).
function Mouse:sync_hover()
  self.last_hover = self.overlay:hovered_index()
end

-- Forget the last hover so the next poll re-applies it (after a click that
-- may have replaced the rows).
function Mouse:reset_hover()
  self.last_hover = nil
end

function Mouse:hovered_index()
  return self.overlay:hovered_index()
end

local function start_loop(self)
  if self.loop_alive then return end   -- reuse the loop that has not ticked out yet
  local loop = global_fn(self, "LoopAsync")
  if not loop then
    warn_once(self, "loop", "LoopAsync not available; mouse hover disabled (click still works)")
    return
  end
  local ok, err = pcall(loop, POLL_MS, function()
    if not self.active then
      self.loop_alive = false
      return true
    end
    local ok2, err2 = pcall(self.ue.in_game_thread, self.ue, function()
      local ok3, err3 = pcall(self.poll, self)
      if not ok3 then
        warn_once(self, "poll", "hover poll failed: " .. tostring(err3))
      end
    end)
    if not ok2 then
      warn_once(self, "poll2", "hover poll scheduling failed: " .. tostring(err2))
    end
    return false
  end)
  if ok then
    self.loop_alive = true
  else
    warn_once(self, "loop", "LoopAsync failed: " .. tostring(err) .. "; mouse hover disabled")
  end
end

-- Applies mouse mode. Idempotent. Returns true if mouse mode is active.
function Mouse:enter()
  if self.active then return true end
  local widget = self.overlay:widget_object()
  if widget == nil then
    warn_once(self, "nowidget", "no overlay widget; mouse disabled (keyboard only)")
    return false
  end
  local pc = self.get_pc and self.get_pc() or nil
  if pc == nil then
    warn_once(self, "nopc", "no local controller; mouse disabled (keyboard only)")
    return false
  end
  self.pc = pc
  local prev = self.ue:get(pc, "bShowMouseCursor")
  self.prev_cursor = prev
  self.ue:set(pc, "bShowMouseCursor", true)
  self.ue:set(pc, "bEnableClickEvents", true)

  local lib = find_lib(self)
  local ok_mode = false
  if lib ~= nil then
    ok_mode = self.ue:call(lib, "SetInputMode_UIOnlyEx", pc, widget, DO_NOT_LOCK, false)
    if not ok_mode then
      ok_mode = self.ue:call(lib, "SetInputMode_GameAndUIEx", pc, widget, DO_NOT_LOCK, false, false)
      if ok_mode then
        if self.ue:call(pc, "SetIgnoreLookInput", true) then self.ignore_look = true end
      end
    end
  end
  if not ok_mode then
    warn_once(self, "mode", "could not change input mode; cursor shown but game input stays active")
  end
  self.active = true
  self.last_hover = nil
  start_loop(self)
  return true
end

-- Restores everything enter() changed. Idempotent.
function Mouse:leave()
  if not self.active then return end
  self.active = false     -- the poll loop sees this and ends itself
  self.last_hover = nil
  local pc = self.pc
  if pc ~= nil and not self.ue:is_valid(pc) then
    pc = self.get_pc and self.get_pc() or nil
  end
  self.pc = nil
  if pc ~= nil then
    self.ue:set(pc, "bShowMouseCursor", self.prev_cursor == true)
    local lib = find_lib(self)
    if lib ~= nil then
      self.ue:call(lib, "SetInputMode_GameOnly", pc, false)
    end
    if self.ignore_look then
      self.ue:call(pc, "SetIgnoreLookInput", false)
    end
  end
  self.ignore_look = false
  self.prev_cursor = nil
end

return M
