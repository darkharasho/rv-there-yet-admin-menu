-- Pure menu state machine: a page stack with a per-page cursor and a single
-- pending-confirmation slot. Zero engine dependency — this module requires
-- nothing but standard Lua so its mouse/keyboard behaviour is unit-testable
-- headless. overlay.lua renders m:view(); app.lua feeds it keyboard events.
-- Pages may be static (item.target is a page table) or dynamic (item.build
-- is called when the submenu opens, so player and checkpoint lists are
-- always fresh).
local M = {}

local Menu = {}
Menu.__index = Menu

local function items_of(page)
  return (type(page) == "table" and page.items) or {}
end

-- The page's items plus a trailing "< Back" row ("Close" on the root page),
-- so the mouse has something to click to go up a level.
local function rows_of(self, page)
  local out = {}
  for i, item in ipairs(items_of(page)) do out[i] = item end
  out[#out + 1] = { id = "__back", kind = "back", label = (#self.stack > 1) and "< Back" or "Close" }
  return out
end

function M.new(spec, opts)
  if type(opts) ~= "table" then
    opts = {}
  end
  if type(spec) ~= "table" then
    spec = { id = "root", title = "", items = {} }
  end
  return setmetatable({
    spec = spec,
    -- Fails SAFE: only an explicit false disables confirmation, so a
    -- wiring slip that drops the key still prompts before "Kill Player".
    opts = { confirm_destructive = opts.confirm_destructive ~= false },
    stack = {},
    pending = nil,
    message = nil,
    open_flag = false,
  }, Menu)
end

function Menu:open()
  self.stack = { { page = self.spec, cursor = 1, query = "" } }
  self.pending = nil
  self.message = nil
  self.open_flag = true
end

function Menu:close()
  self.open_flag = false
  self.pending = nil
  self.message = nil
end

-- One transient line the renderer shows under the rows: "Host only - you
-- are not the session authority", "player no longer in session", "not
-- available on this game version". nil clears it; a non-string degrades to
-- its tostring() rather than erroring inside a HUD hook.
function Menu:set_message(text)
  if text == nil then
    self.message = nil
  else
    self.message = tostring(text)
  end
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
  local n = #rows_of(self, frame.page)
  if index < 1 or index > n or index ~= math.floor(index) then return end
  if index == frame.cursor then return end
  frame.cursor = index
  self.pending = nil
end

local function move_cursor(self, frame, delta)
  local n = #rows_of(self, frame.page)
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
    move_cursor(self, frame, -1)
    self.pending = nil
    return nil
  end

  if event == "down" then
    move_cursor(self, frame, 1)
    self.pending = nil
    return nil
  end

  if event == "cancel" then
    self.pending = nil
    return nil
  end

  local function go_back()
    self.pending = nil
    self.message = nil
    if #self.stack > 1 then
      table.remove(self.stack)
    else
      self.open_flag = false
    end
  end

  if event == "erase" then
    -- Backspace on a search page deletes a typed character; with nothing
    -- typed it is plain "back".
    if frame.page.search and frame.query ~= "" then
      self:set_query(frame, frame.query:sub(1, -2))
      return nil
    end
    event = "back"
  end

  if event == "back" then
    self.pending = nil
    self.message = nil
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

    local item = rows_of(self, frame.page)[frame.cursor]
    if type(item) ~= "table" or item.id == nil then return nil end

    if item.kind == "back" then
      go_back()
      return nil
    end

    if item.kind == "submenu" then
      local page = item.target
      if type(item.build) == "function" then
        -- A dynamic page is built at open time. The builder returns a page,
        -- or nil plus a short reason ("Host only", "no checkpoints loaded")
        -- which becomes the menu message. A throwing builder is the same as
        -- one that returned nothing: this runs inside a key-bind callback.
        local ok, built, reason = pcall(item.build)
        if not ok then
          self.message = "Error: " .. tostring(built):sub(1, 80)
          return nil
        end
        if type(built) ~= "table" then
          self.message = reason and tostring(reason) or "not available"
          return nil
        end
        page = built
      end
      if type(page) == "table" then
        table.insert(self.stack, { page = page, cursor = 1, query = page.query or "" })
        self.message = nil
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

-- A page with a `search(query)` function is filterable: typed characters
-- build a query and the page is rebuilt from it. The rebuilt page carries
-- the query forward (page.query) so its "Next page" frames keep it.
function Menu:set_query(frame, query)
  local ok, page, reason = pcall(frame.page.search, query)
  self.pending = nil
  if not ok then
    self.message = "Error: " .. tostring(page):sub(1, 80)
    return
  end
  if type(page) ~= "table" then
    self.message = reason and tostring(reason) or "not available"
    return
  end
  frame.page = page
  frame.query = query
  frame.cursor = 1
  self.message = nil
end

-- Returns true if the character was taken by a search page.
function Menu:type(ch)
  if not self.open_flag or type(ch) ~= "string" or ch == "" then return false end
  local frame = top_frame(self)
  if not frame or type(frame.page.search) ~= "function" then return false end
  local q = frame.query or ""
  if ch == " " and (q == "" or q:sub(-1) == " ") then return true end
  if #q >= 24 then return true end
  self:set_query(frame, q .. ch:lower())
  return true
end

function Menu:searchable()
  local frame = top_frame(self)
  return self.open_flag and frame ~= nil and type(frame.page.search) == "function"
end

-- Everything the renderer needs and nothing more: no ids, no engine types.
-- A closed menu renders as nothing at all, so a HUD hook that calls view()
-- every frame cannot leave a ghost menu on screen after close(). Every
-- table returned here is freshly built, so a renderer that mutates the
-- view cannot corrupt the state machine.
function Menu:view()
  local frame = top_frame(self)
  if not self.open_flag or not frame then
    return { title = nil, rows = {}, prompt = nil, message = nil }
  end
  local rows = {}
  for i, item in ipairs(rows_of(self, frame.page)) do
    rows[i] = {
      label = item.label,
      selected = (i == frame.cursor),
      kind = item.kind,
      destructive = item.destructive == true,
    }
    -- Only a toggle has an on/off state to draw. Assigned in a branch rather
    -- than with `and/or`, which would turn a legitimately-off toggle into nil
    -- and make it indistinguishable from a row that has no value at all.
    if item.kind == "toggle" then
      local v = item.value
      if type(v) == "function" then
        -- Live state (a player's god mode) is read at draw time.
        local ok, r = pcall(v)
        if ok then v = r else v = nil end
      end
      rows[i].value = v
    end
  end
  local search
  if type(frame.page.search) == "function" then search = frame.query or "" end
  return {
    title = frame.page.title,
    search = search,   -- the typed query on a search page, else nil
    rows = rows,
    prompt = self.pending and self.pending.prompt or nil,
    message = self.message,
  }
end

return M
