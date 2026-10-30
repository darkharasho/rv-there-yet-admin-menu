package.path = "mod/scripts/?.lua;" .. package.path
local overlay = require("lib.overlay")

describe("overlay.format", function()
  it("renders nothing for a closed menu", function()
    assert.equal("", overlay.format({ title = nil, rows = {} }))
    assert.equal("", overlay.format(nil))
  end)

  it("shows the search field line on search pages", function()
    local text = overlay.format({ title = "Spawn item", search = "dyn", rows = {} })
    assert.truthy(text:find("Search: [dyn_]", 1, true))
  end)

  it("draws title, cursor, submenu dots and toggle state", function()
    local text = overlay.format({
      title = "RV Admin",
      rows = {
        { label = "Teleport", kind = "submenu", selected = true },
        { label = "God mode", kind = "toggle", value = true },
        { label = "Speed", kind = "toggle", value = false },
        { label = "Revive", kind = "action" },
      },
    })
    assert.equal(table.concat({
      "== RV Admin ==",
      "> Teleport ...",
      "  God mode [ON]",
      "  Speed [OFF]",
      "  Revive",
    }, "\n"), text)
  end)

  it("appends the confirm prompt and message lines", function()
    local text = overlay.format({
      title = "T", rows = { { label = "Kill", kind = "action", selected = true } },
      prompt = "Confirm: Kill?", message = "Host only",
    })
    assert.truthy(text:find("Confirm: Kill?", 1, true))
    assert.truthy(text:match("Host only$"))
  end)
end)

describe("overlay widget", function()
  local function logger()
    local l = { lines = {} }
    for _, lv in ipairs({ "debug", "info", "warn", "error" }) do
      l[lv] = function(_, m) l.lines[#l.lines + 1] = lv .. ":" .. m end
    end
    return l
  end
  local view = { title = "T", rows = { { label = "A", kind = "action", selected = true } } }

  it("falls back to logging when UMG is unavailable, warning once", function()
    local l = logger()
    local o = overlay.new({ logger = l, env = {}, get_outer = function() return {} end })
    o:render(view)
    o:render({ title = "T", rows = { { label = "B", kind = "action", selected = true } } })
    local warns, infos = 0, 0
    for _, line in ipairs(l.lines) do
      if line:match("^warn") then warns = warns + 1 end
      if line:match("^info:%[menu%]") then infos = infos + 1 end
    end
    assert.equal(1, warns)
    assert.is_true(infos >= 4)
  end)

  it("builds the widget once and reuses the row pool", function()
    local made, vis_by, texts_by, colors_by = 0, {}, {}, {}
    local function obj(name)
      local o = { name = name }
      function o:SetBrushColor(c) colors_by[name] = c end
      function o:SetPadding() end
      function o:SetContent() end
      function o:AddToViewport() end
      function o:SetPosition() end
      function o:SetAutoSize() end
      function o:AddChildToCanvas() return obj("slot") end
      function o:AddChildToVerticalBox() return obj("slot") end
      function o:SetText(t) texts_by[name] = t end
      function o:SetVisibility(v) vis_by[name] = v end
      function o:IsHovered() return name == "RVAdminRow2" end
      -- Any other widget method (SetFont, SetSize, ...) is a no-op.
      return setmetatable(o, { __index = function() return function() end end })
    end
    local env = {
      StaticFindObject = function(path) return path end,
      StaticConstructObject = function(cls, outer, name) made = made + 1; return obj(name) end,
      -- UE4SS exposes FName/FText as callable tables, not functions.
      FName = setmetatable({}, { __call = function(_, s) return s end }),
      FText = setmetatable({}, { __call = function(_, s) return "T:" .. s end }),
    }
    local o = overlay.new({ logger = logger(), env = env, get_outer = function() return {} end })
    local v2 = { title = "T", rows = {
      { label = "A", kind = "action", selected = true },
      { label = "B", kind = "toggle", value = true },
    }, message = "hi" }
    o:render(v2)
    local made_first = made
    o:render(v2)
    assert.equal(made_first, made)                      -- nothing rebuilt
    assert.equal("T:T", texts_by.RVAdminTitle)
    assert.equal("T:A", texts_by.RVAdminRowText1)
    assert.equal("T:B", texts_by.RVAdminRowText2)
    assert.equal("T:ON", texts_by.RVAdminRowSuffix2)
    assert.equal(overlay.COLORS.sel_bg, colors_by.RVAdminRow1)   -- highlighted
    assert.equal(overlay.COLORS.accent, colors_by.RVAdminRowBar1)
    assert.equal(0, colors_by.RVAdminRow2.A)
    assert.equal(0, vis_by.RVAdminRow2)
    assert.equal(1, vis_by.RVAdminRow3)                 -- unused rows collapsed
    assert.equal(1, vis_by.RVAdminPromptBox)
    assert.equal(0, vis_by.RVAdminMessage)
    assert.equal(2, o:hovered_index())
    o:hide()
    assert.equal(1, vis_by.RVAdminMenuWidget)
    assert.is_nil(o:hovered_index())
  end)
end)

describe("overlay.rows", function()
  it("returns label text and highlight flags", function()
    local rows = overlay.rows({ title = "T", rows = {
      { label = "Teleport", kind = "submenu", selected = false },
      { label = "God", kind = "toggle", value = false, selected = true },
      { label = "Heal", kind = "action" },
    } })
    assert.same({
      { text = "Teleport ...", highlighted = false, label = "Teleport", suffix = ">", suffix_tone = "dim", tone = "normal" },
      { text = "God [OFF]", highlighted = true, label = "God", suffix = "OFF", suffix_tone = "off", tone = "normal" },
      { text = "Heal", highlighted = false, label = "Heal", suffix = "", suffix_tone = "dim", tone = "normal" },
    }, rows)
  end)

  it("tones destructive and back rows", function()
    local rows = overlay.rows({ title = "T", rows = {
      { label = "Kill", kind = "action", destructive = true },
      { label = "< Back", kind = "back" },
    } })
    assert.equal("danger", rows[1].tone)
    assert.equal("back", rows[2].tone)
  end)

  it("is empty for a closed menu", function()
    assert.same({}, overlay.rows({ title = nil, rows = {} }))
    assert.same({}, overlay.rows(nil))
  end)
end)
