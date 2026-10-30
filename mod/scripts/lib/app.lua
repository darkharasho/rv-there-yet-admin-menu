-- Wires menu, actions, overlay and keyboard together. main.lua only works
-- out paths and calls M.start; tests drive M.new with fakes.
local menu_mod = require("lib.menu")
local spec_mod = require("lib.spec")
local actions_mod = require("lib.actions")
local overlay_mod = require("lib.overlay")
local mouse_mod = require("lib.mouse")

local M = {}

-- key name -> menu event. RETURN/RIGHT_ARROW select, BACKSPACE/LEFT_ARROW go
-- back (and close at the root).
local KEYS = {
  UP_ARROW = "up",
  DOWN_ARROW = "down",
  RETURN = "select",
  RIGHT_ARROW = "select",
  BACKSPACE = "erase",
  LEFT_ARROW = "back",
}

-- Typing keys for search pages (UE4SS Key names -> character).
local TYPE_KEYS = { SPACE = " " }
for c = string.byte("A"), string.byte("Z") do
  TYPE_KEYS[string.char(c)] = string.char(c)
end
for i, name in ipairs({ "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }) do
  TYPE_KEYS[name] = tostring(i - 1)
end

local App = {}
App.__index = App

-- opts: ue, logger, cfg, overlay (optional), actions (optional)
function M.new(opts)
  local actions = opts.actions or actions_mod.new({ ue = opts.ue, logger = opts.logger, cfg = opts.cfg,
    items = require("lib.items") })
  local menu = menu_mod.new(spec_mod.build(actions), { confirm_destructive = opts.cfg.confirm_destructive })
  local overlay = opts.overlay or overlay_mod.new({
    ue = opts.ue,
    logger = opts.logger,
    get_outer = function() return actions:local_controller() end,
    hint = string.format("Arrows move  |  Enter select  |  Bksp back  |  %s close", tostring(opts.cfg.hotkey)),
  })
  local self = setmetatable({
    ue = opts.ue, logger = opts.logger, cfg = opts.cfg,
    actions = actions, menu = menu, overlay = overlay,
  }, App)
  if opts.cfg.mouse ~= false then
    self.mouse = opts.mouse or mouse_mod.new({
      ue = opts.ue, logger = opts.logger, overlay = overlay, env = opts.env,
      get_pc = function() return actions:local_controller() end,
      on_hover = function(i) self:hover(i) end,
    })
  end
  return self
end

-- Redraws; applies or releases mouse mode to match the menu's open state.
function App:redraw()
  self.overlay:render(self.menu:view())
  if self.mouse then
    local ok, err = pcall(function()
      if self.menu:is_open() then
        self.mouse:enter()
      else
        self.mouse:leave()
      end
    end)
    if not ok then self:mouse_failed(err) end
  end
end

-- A mouse bug must never break keyboard use: log once, then drop the mouse.
function App:mouse_failed(err)
  if self.logger then pcall(self.logger.warn, self.logger, "mouse support failed: " .. tostring(err)) end
  local m = self.mouse
  self.mouse = nil
  if m then pcall(m.leave, m) end
end

local function cursor_of(menu)
  for i, row in ipairs(menu:view().rows) do
    if row.selected then return i end
  end
  return nil
end

-- Mouse hover: moves the selection and redraws only if it changed.
function App:hover(index)
  if not self.menu:is_open() then return end
  local before = cursor_of(self.menu)
  self.menu:hover(index)
  if cursor_of(self.menu) ~= before then self:redraw() end
end

-- Left click: acts on the row under the cursor; ignored over empty space.
function App:click()
  if not self.mouse or not self.menu:is_open() then return end
  local ok, idx = pcall(self.mouse.hovered_index, self.mouse)
  if not ok then self:mouse_failed(idx) return end
  if idx == nil then return end
  self.menu:hover(idx)
  self:handle("select", true)
end

function App:close_menu()
  if not self.menu:is_open() then return end
  self.menu:close()
  self:redraw()
end

function App:toggle()
  if self.menu:is_open() then
    self.menu:close()
  else
    self.menu:open()
  end
  self:redraw()
  if self.mouse then
    local ok, err = pcall(self.mouse.sync_hover, self.mouse)
    if not ok then self:mouse_failed(err) end
  end
end

-- Handles one menu event; ignored while the menu is closed.
function App:handle(event, from_mouse)
  if not self.menu:is_open() then return end
  local cmd = self.menu:input(event)
  if cmd then
    self.menu:set_message(self.actions:run(cmd.action, cmd.target))
  end
  self:redraw()
  if self.mouse then
    -- After a click the rows may have changed under a still mouse: let the
    -- poll re-hover. After a key press, adopt the current hover so a still
    -- mouse does not snap the selection back.
    local ok, err = pcall(function()
      if from_mouse then self.mouse:reset_hover() else self.mouse:sync_hover() end
    end)
    if not ok then self:mouse_failed(err) end
  end
end

-- A typed character: only search pages take it.
function App:type(ch)
  if not self.menu:is_open() then return end
  if not self.menu:type(ch) then return end
  self:redraw()
  if self.mouse then
    local ok, err = pcall(self.mouse.reset_hover, self.mouse)
    if not ok then self:mouse_failed(err) end
  end
end

-- Every handler body runs on the game thread and is pcall-guarded: a bug
-- must never surface as an error inside UE4SS.
function App:wrap(fn)
  return function()
    self.ue:in_game_thread(function()
      local ok, err = pcall(fn)
      if not ok and self.logger then
        pcall(self.logger.error, self.logger, "key handler failed: " .. tostring(err))
      end
    end)
  end
end

function App:bind_keys()
  self.ue:bind_key(self.cfg.hotkey, self:wrap(function() self:toggle() end))
  for key, event in pairs(KEYS) do
    self.ue:bind_key(key, self:wrap(function() self:handle(event) end))
  end
  for key, ch in pairs(TYPE_KEYS) do
    self.ue:bind_key(key, self:wrap(function() self:type(ch) end))
  end
  if self.mouse then
    self.ue:bind_key("LEFT_MOUSE_BUTTON", self:wrap(function() self:click() end))
    self.ue:bind_key("RIGHT_MOUSE_BUTTON", self:wrap(function() self:handle("back", true) end))
    self.ue:bind_key("ESCAPE", self:wrap(function() self:close_menu() end))
  end
end

M.KEYS = KEYS
M.TYPE_KEYS = TYPE_KEYS
return M
