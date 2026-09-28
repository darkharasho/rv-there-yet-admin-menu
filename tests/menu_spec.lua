local menu = require("mod.scripts.lib.menu")

-- Maps item id -> label for the fixture below. view() rows only expose
-- labels (menu.lua knows nothing about ids at render time), so the test
-- helpers resolve an id to a row index via this table.
local LABELS = {
  spawn = "Spawn Item",
  players = "Players",
  kill = "Kill Player",
  heal = "Heal All",
  kick = "Kick",
}

local function index_of(m, id)
  local label = LABELS[id]
  for i, row in ipairs(m:view().rows) do
    if row.label == label then return i end
  end
  return nil
end

local function select_row(m, id)
  local i = index_of(m, id)
  if i then m:hover(i) end
  return i
end

local players_page = {
  id = "players",
  title = "Players",
  items = {
    { id = "kick", label = LABELS.kick, kind = "action" },
  },
}

local spec = {
  id = "root",
  title = "Admin Menu",
  items = {
    { id = "spawn", label = LABELS.spawn, kind = "action" },
    { id = "players", label = LABELS.players, kind = "submenu", target = players_page },
    { id = "kill", label = LABELS.kill, kind = "action", destructive = true },
    { id = "heal", label = LABELS.heal, kind = "toggle" },
  },
}

describe("menu", function()
  it("wraps the cursor at both ends", function()
    local m = menu.new(spec, {}); m:open()
    m:input("up")
    assert.is_true(m:view().rows[#m:view().rows].selected)
    m:input("down")
    assert.is_true(m:view().rows[1].selected)
  end)

  it("requires confirmation before a destructive action", function()
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    select_row(m, "kill")
    assert.is_nil(m:input("select"))            -- first select only prompts
    assert.truthy(m:view().prompt:find("Kill"))
    assert.same({ action = "kill", target = nil }, m:input("select"))
  end)

  it("hover moves the cursor and ignores out-of-range indices", function()
    local m = menu.new(spec, {}); m:open()
    m:hover(2)
    assert.is_true(m:view().rows[2].selected)
    m:hover(0); m:hover(99); m:hover(-1)
    assert.is_true(m:view().rows[2].selected)   -- unchanged, no error
  end)

  it("a click on a destructive row still requires confirmation", function()
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    local i = index_of(m, "kill")
    m:hover(i)
    assert.is_nil(m:input("select"))            -- the click only prompts
    assert.same({ action = "kill", target = nil }, m:input("select"))
  end)

  it("cancel clears the pending confirmation without firing", function()
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    select_row(m, "kill"); m:input("select"); m:input("cancel")
    assert.is_nil(m:view().prompt)
  end)

  it("back leaves a submenu instead of closing the menu", function()
    local m = menu.new(spec, {}); m:open()
    select_row(m, "players"); m:input("select"); m:input("back")
    assert.is_true(m:is_open())
    assert.equal("Admin Menu", m:view().title)
  end)

  it("back at the root closes the menu", function()
    local m = menu.new(spec, {}); m:open(); m:input("back")
    assert.is_false(m:is_open())
  end)

  it("re-hovering the already-selected row preserves a pending confirmation", function()
    -- The subtlest bug in this module: a real mouse re-reports the same row
    -- every frame before the click lands. If hover(i) cleared pending when
    -- i is already the selected row, confirmation would be unreachable by
    -- mouse (every frame's hover would wipe out the first click's prompt).
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    local i = index_of(m, "kill")
    m:hover(i)
    m:input("select")                            -- first click: sets pending
    assert.truthy(m:view().prompt)
    m:hover(i)                                    -- same row re-reported
    assert.truthy(m:view().prompt)                -- still pending
    assert.same({ action = "kill", target = nil }, m:input("select"))
  end)

  it("hovering a different row clears a pending confirmation", function()
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    select_row(m, "kill"); m:input("select")
    assert.truthy(m:view().prompt)
    select_row(m, "spawn")
    assert.is_nil(m:view().prompt)
    -- the previously-confirmed kill must not fire; spawn is non-destructive
    -- so selecting it now fires spawn immediately, not the stale kill.
    assert.same({ action = "spawn", target = nil }, m:input("select"))
  end)

  it("input on a closed menu is a no-op", function()
    local m = menu.new(spec, {})
    assert.is_nil(m:input("select"))
    assert.is_nil(m:input("up"))
    assert.same({ title = nil, rows = {}, prompt = nil }, m:view())
  end)

  it("an unknown event string is a no-op", function()
    local m = menu.new(spec, {}); m:open()
    assert.is_nil(m:input("jump"))
    assert.is_true(m:view().rows[1].selected)
  end)

  it("hover rejects a non-number argument", function()
    local m = menu.new(spec, {}); m:open()
    m:hover(2)
    m:hover("2")
    assert.is_true(m:view().rows[2].selected)
  end)

  it("a non-destructive action fires immediately without confirmation", function()
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    select_row(m, "spawn")
    assert.same({ action = "spawn", target = nil }, m:input("select"))
  end)

  it("a toggle item fires like an action", function()
    local m = menu.new(spec, {}); m:open()
    select_row(m, "heal")
    assert.same({ action = "heal", target = nil }, m:input("select"))
  end)

  it("entering a submenu resets its cursor to the first row", function()
    local m = menu.new(spec, {}); m:open()
    select_row(m, "players"); m:input("select")
    assert.equal("Players", m:view().title)
    assert.is_true(m:view().rows[1].selected)
  end)
end)
