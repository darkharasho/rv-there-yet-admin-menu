-- Renders menu.lua's view() on screen. The game's HUD draw hook never fires
-- (docs/game-objects.md section 8), so the menu is a UMG widget built from
-- Lua: UserWidget -> WidgetTree -> CanvasPanel -> Border(background) ->
-- VerticalBox -> [title TextBlock, MAX_ROWS row Borders (each wrapping a
-- TextBlock), prompt TextBlock, message TextBlock]. Row Borders are
-- hit-testable (Visible) so IsHovered() works for the mouse; unused rows in
-- the fixed pool are collapsed.
--
-- M.format() and M.rows() are pure and unit-tested. The widget half cannot
-- be tested headless: every engine call in it is a GUESS until the in-game
-- test. Each step is pcall-guarded; if UMG fails the overlay logs one
-- warning and falls back to writing each redraw to the log as INFO lines.
-- It never throws.
local M = {}

-- ESlateVisibility
local VISIBLE, COLLAPSED = 0, 1

-- Row pool size. The largest page is the 15-item spawn page plus paging rows.
M.MAX_ROWS = 24

-- Colours are written as sRGB hex and converted to the linear values UMG
-- expects (FLinearColor); passing sRGB straight through looks washed out.
local function hex(h, a)
  local function ch(i)
    return (tonumber(h:sub(i, i + 1), 16) / 255) ^ 2.2
  end
  return { R = ch(1), G = ch(3), B = ch(5), A = a or 1 }
end

local C = {
  panel     = hex("0e1016", 0.92),
  divider   = hex("ffffff", 0.10),
  clear     = { R = 0, G = 0, B = 0, A = 0 },
  accent    = hex("f0a040"),
  sel_bg    = hex("f0a040", 0.18),
  danger    = hex("e05050"),
  danger_bg = hex("e05050", 0.18),
  title     = hex("f0a040"),
  text      = hex("d8dbe0"),
  text_sel  = hex("ffffff"),
  text_dng  = hex("ff8a8a"),
  dim       = hex("8a8f98"),
  faint     = hex("6f7580"),
  on        = hex("5fd07a"),
  prompt    = hex("ffb0b0"),
  message   = hex("b8c4d6"),
  field     = hex("ffffff", 0.07),
}
M.COLORS = C

local SIZE = { title = 14, row = 17, small = 11 }
local WIDTH = 320

local function row_text(row)
  local text = tostring(row.label)
  if row.kind == "submenu" then
    text = text .. " ..."
  elseif row.kind == "toggle" then
    text = text .. (row.value and " [ON]" or " [OFF]")
  end
  return text
end

-- Pure. view -> list of rows, one per menu row, in order. Empty for a
-- closed menu. text is the one-line form used by the log fallback; label,
-- suffix and tone drive the styled widget.
--   tone: "normal" | "danger" (destructive action) | "back"
--   suffix: ">" (submenu), "ON"/"OFF" (toggle) or "" ; suffix_tone: "dim"|"on"|"off"
function M.rows(view)
  local out = {}
  if type(view) ~= "table" or view.title == nil then return out end
  for i, row in ipairs(view.rows or {}) do
    local suffix, suffix_tone = "", "dim"
    if row.kind == "submenu" then
      suffix = ">"
    elseif row.kind == "toggle" then
      suffix, suffix_tone = (row.value and "ON" or "OFF"), (row.value and "on" or "off")
    end
    local tone = "normal"
    if row.kind == "back" then tone = "back" elseif row.destructive then tone = "danger" end
    out[i] = {
      text = row_text(row),
      highlighted = row.selected == true,
      label = tostring(row.label),
      suffix = suffix,
      suffix_tone = suffix_tone,
      tone = tone,
    }
  end
  return out
end

-- Pure. Takes menu:view() and returns the text block, or "" for a closed
-- menu (view.title == nil). Used for the log fallback.
function M.format(view)
  if type(view) ~= "table" or view.title == nil then return "" end
  local lines = { "== " .. tostring(view.title) .. " ==" }
  if view.search then
    lines[#lines + 1] = "Search: [" .. view.search .. "_]"
  end
  for _, r in ipairs(M.rows(view)) do
    lines[#lines + 1] = (r.highlighted and "> " or "  ") .. r.text
  end
  if view.prompt then
    lines[#lines + 1] = ""
    lines[#lines + 1] = tostring(view.prompt) .. " (Enter = yes, any other key = no)"
  end
  if view.message then
    lines[#lines + 1] = ""
    lines[#lines + 1] = tostring(view.message)
  end
  return table.concat(lines, "\n")
end

local Overlay = {}
Overlay.__index = Overlay

-- opts: ue (adapter, for is_valid), logger, get_outer (function -> object to
-- own the widget), env (global table; tests inject fakes, default _G).
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    ue = opts.ue,
    logger = opts.logger,
    get_outer = opts.get_outer,
    hint = opts.hint,
    env = opts.env or _G,
    widget = nil,
    parts = nil,       -- { title, rows = { {border,text}... }, prompt, message }
    shown = 0,         -- number of visible rows
    failed = false,   -- UMG construction failed: log-only mode
    last_logged = nil,
  }, Overlay)
end

local function note(self, level, msg)
  if self.logger then pcall(self.logger[level], self.logger, msg) end
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

local function widget_valid(self)
  if self.widget == nil then return false end
  if self.ue then return self.ue:is_valid(self.widget) and self.parts ~= nil end
  return true
end

-- Builds the widget tree. Returns true, or false plus a reason. Called
-- inside pcall, so a plain error() is fine here.
local function construct(self)
  local find = global_fn(self, "StaticFindObject")
  local make = global_fn(self, "StaticConstructObject")
  local fname = global_fn(self, "FName")
  if not (find and make) then
    error(string.format("missing UE4SS globals: StaticFindObject=%s StaticConstructObject=%s",
      type(lookup(self.env, "StaticFindObject")), type(lookup(self.env, "StaticConstructObject"))))
  end
  -- Object names are cosmetic. Without FName, let UE4SS pick the name by
  -- leaving the argument out (passing an explicit nil could be rejected).
  if not fname then
    note(self, "warn", "FName global unavailable; constructing widgets without names")
    fname = function() return nil end
  end
  local raw_make = make
  make = function(cls, outer, name)
    if name == nil then return raw_make(cls, outer) end
    return raw_make(cls, outer, name)
  end
  local function class(path)
    local c = find(path)
    if c == nil then error("class not found: " .. path) end
    return c
  end

  -- GUESS: the owner. A PlayerController is the usual outer for a widget;
  -- the brief also allows the game instance.
  local outer = self.get_outer and self.get_outer() or nil
  if outer == nil then error("no outer object (no local controller yet)") end

  -- Cosmetic steps (fonts, rounded corners, slot layout) may not all work
  -- through UE4SS; each is tried on its own and a failure only costs looks.
  local function try(what, fn)
    local ok, err = pcall(fn)
    if not ok and not (self.style_warned or {})[what] then
      self.style_warned = self.style_warned or {}
      self.style_warned[what] = true
      note(self, "warn", "overlay style step '" .. what .. "' failed: " .. tostring(err))
    end
  end

  local widget = make(class("/Script/UMG.UserWidget"), outer, fname("RVAdminMenuWidget"))
  local tree = make(class("/Script/UMG.WidgetTree"), widget, fname("RVAdminTree"))
  widget.WidgetTree = tree
  local canvas = make(class("/Script/UMG.CanvasPanel"), tree, fname("RVAdminCanvas"))
  tree.RootWidget = canvas

  local function new(cls, name) return make(class("/Script/UMG." .. cls), tree, fname(name)) end
  local function text_block(name, size, bold)
    local tb = new("TextBlock", name)
    -- Edited in place before AddToViewport, so the Slate widget is built
    -- with these values and no SetFont round-trip is needed.
    try("font", function()
      tb.Font.Size = size
      if bold then tb.Font.TypefaceFontName = fname("Bold") end
    end)
    return tb
  end
  local function vslot(slot, l, t, r, b)
    try("vbox slot", function() slot:SetPadding({ Left = l, Top = t, Right = r, Bottom = b }) end)
  end
  local function divider(name)
    local sb = new("SizeBox", name .. "Box")
    try("divider", function() sb:SetHeightOverride(1) end)
    local line = new("Border", name)
    line:SetBrushColor(C.divider)
    line:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    sb:SetContent(line)
    return sb
  end

  local bg = new("Border", "RVAdminBorder")
  try("rounded corners", function()
    bg.Background.DrawAs = 4                  -- ESlateBrushDrawType::RoundedBox
    bg.Background.OutlineSettings.RoundingType = 0   -- FixedRadius
    local r = bg.Background.OutlineSettings.CornerRadii
    r.X, r.Y, r.Z, r.W = 8, 8, 8, 8
  end)
  bg:SetBrushColor(C.panel)
  bg:SetPadding({ Left = 0, Top = 12, Right = 0, Bottom = 10 })
  local slot = canvas:AddChildToCanvas(bg)
  slot:SetPosition({ X = 40, Y = 120 })
  slot:SetAutoSize(true)

  local width = new("SizeBox", "RVAdminWidth")
  try("width", function() width:SetMinDesiredWidth(WIDTH) end)
  bg:SetContent(width)
  local vbox = new("VerticalBox", "RVAdminVBox")
  width:SetContent(vbox)

  local title = text_block("RVAdminTitle", SIZE.title, true)
  try("color", function() title:SetColorAndOpacity({ SpecifiedColor = C.title, ColorUseRule = 0 }) end)
  vslot(vbox:AddChildToVerticalBox(title), 16, 0, 16, 8)
  vslot(vbox:AddChildToVerticalBox(divider("RVAdminDivTop")), 16, 0, 16, 6)

  -- Search field, shown only on search pages: a rounded dark box with the
  -- typed text (or a placeholder) and a "|" cursor.
  local search_box = new("Border", "RVAdminSearchBox")
  try("rounded corners", function()
    search_box.Background.DrawAs = 4
    search_box.Background.OutlineSettings.RoundingType = 0
    local r = search_box.Background.OutlineSettings.CornerRadii
    r.X, r.Y, r.Z, r.W = 4, 4, 4, 4
  end)
  search_box:SetBrushColor(C.field)
  search_box:SetPadding({ Left = 10, Top = 6, Right = 10, Bottom = 6 })
  local search_text = text_block("RVAdminSearchText", SIZE.row - 2, false)
  search_box:SetContent(search_text)
  search_box:SetVisibility(COLLAPSED)
  vslot(vbox:AddChildToVerticalBox(search_box), 16, 0, 16, 6)

  local rows = {}
  for i = 1, M.MAX_ROWS do
    local rb = new("Border", "RVAdminRow" .. i)
    rb:SetBrushColor(C.clear)
    rb:SetPadding({ Left = 0, Top = 5, Right = 16, Bottom = 5 })
    local hb = new("HorizontalBox", "RVAdminRowBox" .. i)
    rb:SetContent(hb)
    -- Accent bar on the left edge: a 3px-wide SizeBox around a coloured Border.
    local barbox = new("SizeBox", "RVAdminRowBarBox" .. i)
    try("accent bar", function() barbox:SetWidthOverride(3) end)
    local bar = new("Border", "RVAdminRowBar" .. i)
    bar:SetBrushColor(C.clear)
    barbox:SetContent(bar)
    hb:AddChildToHorizontalBox(barbox)
    local tb = text_block("RVAdminRowText" .. i, SIZE.row, false)
    local ls = hb:AddChildToHorizontalBox(tb)
    try("row layout", function()
      ls:SetSize({ SizeRule = 1, Value = 1 })   -- Fill
      ls:SetPadding({ Left = 13, Top = 0, Right = 8, Bottom = 0 })
      ls:SetVerticalAlignment(2)                -- Center
    end)
    local sx = text_block("RVAdminRowSuffix" .. i, SIZE.row, true)
    local ss = hb:AddChildToHorizontalBox(sx)
    try("row layout", function() ss:SetVerticalAlignment(2) end)
    rb:SetVisibility(COLLAPSED)
    vbox:AddChildToVerticalBox(rb)
    rows[i] = { border = rb, text = tb, bar = bar, suffix = sx }
  end

  local prompt_box = new("Border", "RVAdminPromptBox")
  prompt_box:SetBrushColor(C.danger_bg)
  prompt_box:SetPadding({ Left = 8, Top = 5, Right = 8, Bottom = 5 })
  local prompt = text_block("RVAdminPrompt", SIZE.small + 1, false)
  try("color", function() prompt:SetColorAndOpacity({ SpecifiedColor = C.prompt, ColorUseRule = 0 }) end)
  prompt_box:SetContent(prompt)
  vslot(vbox:AddChildToVerticalBox(prompt_box), 16, 8, 16, 0)
  local message = text_block("RVAdminMessage", SIZE.small + 1, false)
  try("color", function() message:SetColorAndOpacity({ SpecifiedColor = C.message, ColorUseRule = 0 }) end)
  try("wrap", function() message:SetAutoWrapText(true) end)
  vslot(vbox:AddChildToVerticalBox(message), 16, 8, 16, 0)

  local hint
  if self.hint then
    vslot(vbox:AddChildToVerticalBox(divider("RVAdminDivBottom")), 16, 8, 16, 6)
    hint = text_block("RVAdminHint", SIZE.small, false)
    try("color", function() hint:SetColorAndOpacity({ SpecifiedColor = C.faint, ColorUseRule = 0 }) end)
    vslot(vbox:AddChildToVerticalBox(hint), 16, 0, 16, 0)
  end
  widget:AddToViewport(1000)
  self.widget = widget
  self.parts = { title = title, search_box = search_box, search_text = search_text, rows = rows, prompt = prompt, prompt_box = prompt_box,
    message = message, hint = hint }
  self.hint_drawn = false
  self.shown = 0
  return true
end

local function ensure_widget(self)
  if widget_valid(self) then return true end
  if self.widget ~= nil then
    note(self, "info", "overlay widget became invalid; recreating")
    self.widget, self.parts, self.shown = nil, nil, 0
  end
  local ok, err = pcall(construct, self)
  if not ok then
    self.widget, self.parts, self.shown = nil, nil, 0
    if not self.failed then
      note(self, "warn", "UMG overlay unavailable (" .. tostring(err) ..
        "); falling back to logging the menu")
    end
    self.failed = true
    return false
  end
  self.failed = false
  return true
end

local function set_text(self, block, str)
  local ftext = global_fn(self, "FText")
  if not ftext then error("FText global unavailable (" .. type(lookup(self.env, "FText")) .. ")") end
  local ok, txt = pcall(ftext, str)
  if not ok then error("FText(str) failed: " .. tostring(txt)) end
  block:SetText(txt)
end

local function set_color(block, c)
  -- Colour is cosmetic: never let it abort a redraw.
  pcall(function() block:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
end

local TEXT_TONE = { normal = C.text, danger = C.text_dng, back = C.dim }
local SUFFIX_TONE = { dim = C.faint, on = C.on, off = C.faint }

local function draw(self, view)
  local p = self.parts
  set_text(self, p.title, string.upper(tostring(view.title)))
  if p.hint and not self.hint_drawn then
    set_text(self, p.hint, self.hint)
    self.hint_drawn = true
  end
  if view.search then
    if view.search == "" then
      set_text(self, p.search_text, "Type to search...")
      set_color(p.search_text, C.faint)
    else
      set_text(self, p.search_text, view.search .. "|")
      set_color(p.search_text, C.text_sel)
    end
    p.search_box:SetVisibility(VISIBLE)
  else
    p.search_box:SetVisibility(COLLAPSED)
  end
  local rows = M.rows(view)
  local n = math.min(#rows, M.MAX_ROWS)
  if #rows > n and not self.truncated then
    self.truncated = true
    note(self, "warn", string.format("menu page has %d rows; only the first %d are drawn", #rows, n))
  end
  for i = 1, M.MAX_ROWS do
    local pr, r = p.rows[i], rows[i]
    if r and i <= n then
      set_text(self, pr.text, r.label)
      set_text(self, pr.suffix, r.suffix)
      local danger = r.tone == "danger"
      if r.highlighted then
        pr.border:SetBrushColor(danger and C.danger_bg or C.sel_bg)
        pr.bar:SetBrushColor(danger and C.danger or C.accent)
        set_color(pr.text, danger and C.text_dng or C.text_sel)
      else
        pr.border:SetBrushColor(C.clear)
        pr.bar:SetBrushColor(C.clear)
        set_color(pr.text, TEXT_TONE[r.tone] or C.text)
      end
      set_color(pr.suffix, SUFFIX_TONE[r.suffix_tone] or C.faint)
      pr.border:SetVisibility(VISIBLE)
    else
      pr.border:SetVisibility(COLLAPSED)
    end
  end
  self.shown = n
  if view.prompt then
    set_text(self, p.prompt, tostring(view.prompt) .. "  Enter = yes")
    p.prompt_box:SetVisibility(VISIBLE)
  else
    p.prompt_box:SetVisibility(COLLAPSED)
  end
  if view.message then
    set_text(self, p.message, tostring(view.message))
    p.message:SetVisibility(VISIBLE)
  else
    p.message:SetVisibility(COLLAPSED)
  end
  self.widget:SetVisibility(VISIBLE)
end

-- view == menu:view(). A closed menu hides the widget.
function Overlay:render(view)
  local str = M.format(view)
  if str == "" then
    self.last_logged = nil
    self.shown = 0
    if self.widget ~= nil and widget_valid(self) then
      pcall(function() self.widget:SetVisibility(COLLAPSED) end)
    end
    return
  end
  if ensure_widget(self) then
    local ok, err = pcall(draw, self, view)
    if not ok then
      note(self, "warn", "overlay redraw failed: " .. tostring(err))
      self.widget, self.parts, self.shown = nil, nil, 0   -- rebuild on the next redraw
    else
      return
    end
  end
  -- Log-only fallback: one INFO line per menu line.
  if str ~= self.last_logged then
    self.last_logged = str
    for line in (str .. "\n"):gmatch("(.-)\n") do
      note(self, "info", "[menu] " .. line)
    end
  end
end

-- The live widget (for SetInputMode focus), or nil in log-only mode.
function Overlay:widget_object()
  if self.widget ~= nil and widget_valid(self) then return self.widget end
  return nil
end

-- 1-based index of the first visible row whose Border reports IsHovered(),
-- or nil. Never throws.
function Overlay:hovered_index()
  if self.parts == nil or self.shown == 0 or not widget_valid(self) then return nil end
  for i = 1, self.shown do
    local border = self.parts.rows[i].border
    local ok, hovered = pcall(function() return border:IsHovered() end)
    if not ok then
      if not self.hover_warned then
        self.hover_warned = true
        note(self, "warn", "row IsHovered() failed: " .. tostring(hovered))
      end
      return nil
    end
    if hovered == true then return i end
  end
  return nil
end

function Overlay:hide()
  self:render(nil)
end

return M
