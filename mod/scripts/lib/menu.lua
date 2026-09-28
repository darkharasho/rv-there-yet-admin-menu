-- Pure menu state machine: a page stack with a per-page cursor and a single
-- pending-confirmation slot. Zero engine dependency — this module requires
-- nothing but standard Lua so its mouse/keyboard behaviour is unit-testable
-- headless. A later task renders m:view() to the HUD and turns a mouse pixel
-- position into a row index for m:hover().
local M = {}

local Menu = {}
Menu.__index = Menu

local function items_of(page)
  return (type(page) == "table" and page.items) or {}
end

function M.new(spec, opts)
  opts = opts or {}
  if type(spec) ~= "table" then
    spec = { id = "root", title = "", items = {} }
  end
  return setmetatable({
    spec = spec,
    opts = { confirm_destructive = opts.confirm_destructive == true },
    stack = {},
    pending = nil,
    open_flag = false,
  }, Menu)
end

function Menu:open()
  self.stack = { { page = self.spec, cursor = 1 } }
  self.pending = nil
  self.open_flag = true
end

function Menu:close()
  self.open_flag = false
  self.pending = nil
end

function Menu:is_open()
  return self.open_flag == true
end

local function top_frame(self)
  return self.stack[#self.stack]
end

-- Moves the cursor to a row by 1-based index, rejecting anything outside
-- 1..#rows rather than clamping into range: a mouse outside the list must
-- not drag the selection to an edge row. Re-hovering the already-selected
-- row (a real mouse re-reports the same row every frame before a click
-- lands) is a no-op that preserves any pending confirmation; only an actual
-- move to a different row clears it.
function Menu:hover(index)
  if not self.open_flag then return end
  if type(index) ~= "number" then return end
  local frame = top_frame(self)
  if not frame then return end
  local n = #items_of(frame.page)
  if index < 1 or index > n or index ~= math.floor(index) then return end
  if index == frame.cursor then return end
  frame.cursor = index
  self.pending = nil
end

local function move_cursor(frame, delta)
  local n = #items_of(frame.page)
  if n == 0 then return end
  local cursor = frame.cursor + delta
  if cursor < 1 then
    cursor = n
  elseif cursor > n then
    cursor = 1
  end
  frame.cursor = cursor
end

-- event in "up"|"down"|"select"|"back"|"cancel". Returns a command table
-- { action = id, target = id } only when an action actually fires,
-- otherwise nil. Unknown events and input while closed are no-ops.
function Menu:input(event)
  if not self.open_flag then return nil end
  local frame = top_frame(self)
  if not frame then return nil end

  if event == "up" then
    move_cursor(frame, -1)
    self.pending = nil
    return nil
  end

  if event == "down" then
    move_cursor(frame, 1)
    self.pending = nil
    return nil
  end

  if event == "cancel" then
    self.pending = nil
    return nil
  end

  if event == "back" then
    self.pending = nil
    if #self.stack > 1 then
      table.remove(self.stack)
    else
      self.open_flag = false
    end
    return nil
  end

  if event == "select" then
    if self.pending then
      local cmd = self.pending.cmd
      self.pending = nil
      return cmd
    end

    local item = items_of(frame.page)[frame.cursor]
    if type(item) ~= "table" or item.id == nil then return nil end

    if item.kind == "submenu" then
      if type(item.target) == "table" then
        table.insert(self.stack, { page = item.target, cursor = 1 })
      end
      return nil
    end

    if item.kind == "action" or item.kind == "toggle" then
      local cmd = { action = item.id }
      if item.target ~= nil then cmd.target = item.target end
      if item.destructive == true and self.opts.confirm_destructive then
        self.pending = { cmd = cmd, prompt = string.format("Confirm: %s?", tostring(item.label)) }
        return nil
      end
      return cmd
    end

    return nil
  end

  return nil
end

-- Everything the renderer needs and nothing more: no ids, no engine types.
function Menu:view()
  local frame = top_frame(self)
  if not frame then
    return { title = nil, rows = {}, prompt = nil }
  end
  local rows = {}
  for i, item in ipairs(items_of(frame.page)) do
    rows[i] = { label = item.label, selected = (i == frame.cursor) }
  end
  return {
    title = frame.page.title,
    rows = rows,
    prompt = self.pending and self.pending.prompt or nil,
  }
end

return M
