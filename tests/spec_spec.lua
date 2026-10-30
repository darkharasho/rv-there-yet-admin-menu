package.path = "mod/scripts/?.lua;" .. package.path
local menu_mod = require("lib.menu")
local spec = require("lib.spec")

-- Stand-in for actions.lua: only what spec.lua calls.
local function fake_actions(over)
  local a = {
    ITEMS_PER_PAGE = 15, god_all = false,
    is_host = function() return true end,
    players = function() return {} end,
    checkpoints = function() return {} end,
    item_list = function() return nil, "no item list available" end,
    player_god = function() return true end,
    player_speed = function() return false end,
    me_god = function() return false end,
  }
  for k, v in pairs(over or {}) do a[k] = v end
  return a
end

local function open_path(m, ...)
  for _, label in ipairs({ ... }) do
    local view = m:view()
    for i, row in ipairs(view.rows) do
      if row.label == label then m:hover(i) end
    end
    m:input("select")
  end
end

local function labels(m)
  local out = {}
  for i, r in ipairs(m:view().rows) do
    if r.kind ~= "back" then out[i] = r.label end   -- skip the trailing Back/Close row
  end
  return out
end

describe("menu spec dynamic pages", function()
  it("lists players and opens a per-player page with a destructive Kill", function()
    local a = fake_actions({ players = function()
      return { { ref = { name = "Ann" } }, { ref = { name = "Bob" } } }
    end })
    local m = menu_mod.new(spec.build(a), { confirm_destructive = true })
    m:open()
    open_path(m, "Players")
    assert.same({ "Ann", "Bob" }, labels(m))
    open_path(m, "Bob")
    assert.equal("Bob", m:view().title)
    open_path(m, "Kill")
    assert.equal("Confirm: Kill?", m:view().prompt)
    local god
    for _, r in ipairs(m:view().rows) do if r.label == "God mode" then god = r end end
    assert.is_true(god.value)
  end)

  it("shows 'Host only' instead of host pages on a client", function()
    local m = menu_mod.new(spec.build(fake_actions({ is_host = function() return false end })))
    m:open()
    open_path(m, "Players")
    assert.equal("Host only", m:view().message)
    assert.equal("RV Admin", m:view().title)
    open_path(m, "Everyone")
    assert.equal("Host only", m:view().message)
  end)

  it("lists only loaded checkpoints, or says none are loaded", function()
    local m = menu_mod.new(spec.build(fake_actions()))
    m:open()
    open_path(m, "Teleport", "Everyone to checkpoint")
    assert.equal("no checkpoints loaded", m:view().message)
    local a = fake_actions({ checkpoints = function()
      return { { index = 2 }, { index = 5 } }
    end })
    m = menu_mod.new(spec.build(a))
    m:open()
    open_path(m, "Teleport", "Everyone to checkpoint")
    assert.same({ "Checkpoint 2", "Checkpoint 5" }, labels(m))
  end)

  it("offers checkpoints 0..15 for Me-to and a confirmed Restart", function()
    local m = menu_mod.new(spec.build(fake_actions()), { confirm_destructive = true })
    m:open()
    open_path(m, "Teleport", "Me to checkpoint")
    assert.equal(16, #labels(m))
    m:input("back")
    open_path(m, "Restart at checkpoint", "Checkpoint 3")
    assert.truthy(m:view().prompt)
  end)

  it("pages the item list 15 at a time with Next page", function()
    local list = {}
    for i = 1, 20 do list[i] = { name = "Item" .. i, class = i } end
    local m = menu_mod.new(spec.build(fake_actions({ item_list = function() return list end })))
    m:open()
    open_path(m, "Spawn item")
    assert.equal(16, #labels(m))
    assert.equal("Next page", labels(m)[16])
    open_path(m, "Next page")
    assert.equal(5, #labels(m) - 0)
    assert.equal("Item16", labels(m)[1])
  end)

  it("filters the item list as you type and erases with backspace", function()
    local list = { { name = "Axe", class = 1 }, { name = "Dynamite with fuse", class = 2 },
      { name = "Dynamite with trigger", class = 3 }, { name = "Flare", class = 4 } }
    local m = menu_mod.new(spec.build(fake_actions({ item_list = function() return list end })))
    m:open()
    open_path(m, "Spawn item")
    for ch in ("dyn"):gmatch(".") do assert.is_true(m:type(ch)) end
    assert.same({ "Dynamite with fuse", "Dynamite with trigger" }, labels(m))
    assert.equal("Spawn item (1-2 of 2)", m:view().title)
    assert.equal("dyn", m:view().search)
    m:type(" "); m:type("t"); m:type("r")
    assert.same({ "Dynamite with trigger" }, labels(m))
    m:type("q")
    assert.equal("Spawn item: no matches", m:view().title)
    for _ = 1, 7 do m:input("erase") end
    assert.equal(4, #labels(m))
    m:input("erase")   -- nothing left to erase: goes back to the root
    assert.equal("RV Admin", m:view().title)
  end)

  it("keeps the query on the next page of results", function()
    local list = {}
    for i = 1, 20 do list[i] = { name = "Item" .. i, class = i } end
    list[21] = { name = "Other", class = 21 }
    local m = menu_mod.new(spec.build(fake_actions({ item_list = function() return list end })))
    m:open()
    open_path(m, "Spawn item")
    m:type("i")
    open_path(m, "Next page")
    assert.equal("Spawn item (16-20 of 20)", m:view().title)
    assert.equal("i", m:view().search)
    m:input("erase")
    assert.equal(15, #labels(m) - 1)   -- unfiltered first page plus Next page
  end)

  it("ignores typing on pages without search", function()
    local m = menu_mod.new(spec.build(fake_actions()))
    m:open()
    assert.is_false(m:type("a"))
    assert.is_nil(m:view().search)
  end)

  it("reports an unreadable item list", function()
    local m = menu_mod.new(spec.build(fake_actions()))
    m:open()
    open_path(m, "Spawn item")
    assert.equal("no item list available", m:view().message)
  end)
end)

describe("menu dynamic submenu errors", function()
  it("turns a throwing builder into a message", function()
    local m = menu_mod.new({ id = "r", title = "R", items = {
      { id = "x", label = "X", kind = "submenu", build = function() error("boom") end } } })
    m:open()
    m:input("select")
    assert.truthy(m:view().message:match("^Error"))
    assert.equal("R", m:view().title)
  end)

  it("evaluates function toggle values at draw time", function()
    local on = false
    local m = menu_mod.new({ id = "r", title = "R", items = {
      { id = "t", label = "T", kind = "toggle", value = function() return on end } } })
    m:open()
    assert.is_false(m:view().rows[1].value)
    on = true
    assert.is_true(m:view().rows[1].value)
  end)
end)
