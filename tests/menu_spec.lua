local menu = require("mod.scripts.lib.menu")

-- Maps item id -> label for the fixture below. view() rows only expose
-- labels (menu.lua knows nothing about ids at render time), so the test
-- helpers resolve an id to a row index via this table.
local LABELS = {
  spawn = "Spawn Item",
  players = "Players",
  kill = "Kill Player",
  heal = "Heal All",
  godmode = "God Mode",
  kick = "Kick",
}

-- Fails loudly on a typo: a silent nil here would leave the cursor on row
-- 1 and let tests pass for the wrong reason. Test-only code, so assert is
-- the right tool (the no-error rule covers mod/ and tools/).
local function index_of(m, id)
  local label = LABELS[id]
  assert(label, "no label for id: " .. tostring(id))
  for i, row in ipairs(m:view().rows) do
    if row.label == label then return i end
  end
  error("no visible row labelled " .. tostring(label))
end

local function select_row(m, id)
  local i = index_of(m, id)
  m:hover(i)
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
    { id = "heal", label = LABELS.heal, kind = "toggle", value = true },
    { id = "godmode", label = LABELS.godmode, kind = "toggle", value = false },
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
    local m = menu.new(spec, { confirm_destructive = true }); m:open()
    select_row(m, "kill"); m:input("select")     -- arm a pending confirmation
    local stack_depth_before = #m.stack
    assert.is_nil(m:input("jump"))
    assert.is_true(m:view().rows[index_of(m, "kill")].selected)
    assert.truthy(m:view().prompt)                -- pending confirmation untouched
    assert.equal(stack_depth_before, #m.stack)     -- page/stack depth unchanged
  end)

  it("selecting a destructive row fires immediately when confirm_destructive is false", function()
    local m = menu.new(spec, { confirm_destructive = false }); m:open()
    select_row(m, "kill")
    assert.same({ action = "kill", target = nil }, m:input("select"))
    assert.is_nil(m:view().prompt)
  end)

  it("confirmation defaults ON for omitted, empty and misnamed opts", function()
    -- Fail-safe: anything that is not an explicit false must still prompt.
    -- A wiring slip that drops or misspells the key must never turn
    -- "Kill Player" into a one-click action.
    -- Array of names, not a keyed table: a nil value in a table
    -- constructor would silently drop the "omitted opts" case.
    local cases = { "omitted opts", "empty opts", "misnamed key", "non-table opts" }
    local opts_for = {
      ["empty opts"] = {},
      ["misnamed key"] = { confirmdestructive = false },
      ["non-table opts"] = 5,
    }
    for _, name in ipairs(cases) do
      local m = menu.new(spec, opts_for[name]); m:open()
      select_row(m, "kill")
      assert.is_nil(m:input("select"), name .. " fired without confirming")
      assert.truthy(m:view().prompt, name .. " showed no prompt")
      assert.same({ action = "kill", target = nil }, m:input("select"))
    end
  end)

  it("menu.new tolerates a non-table opts argument", function()
    local m = menu.new(spec, 5); m:open()
    assert.is_true(m:is_open())
    select_row(m, "spawn")
    assert.same({ action = "spawn", target = nil }, m:input("select"))
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

  it("view is empty once the menu is closed, not just before it is opened", function()
    -- A HUD hook calls view() every frame; a non-empty view after close()
    -- draws a ghost menu that never goes away.
    local m = menu.new(spec, {}); m:open()
    m:close()
    assert.is_false(m:is_open())
    assert.same({ title = nil, rows = {}, prompt = nil, message = nil }, m:view())
  end)

  it("view is empty after back closes the menu at the root", function()
    local m = menu.new(spec, {}); m:open()
    m:input("back")
    assert.is_false(m:is_open())
    assert.same({}, m:view().rows)
    assert.is_nil(m:view().title)
  end)

  it("view rows carry kind, destructive and a toggle's value", function()
    local m = menu.new(spec, {}); m:open()
    local rows = m:view().rows
    local kill = rows[index_of(m, "kill")]
    assert.equal("action", kill.kind)
    assert.is_true(kill.destructive)

    local players = rows[index_of(m, "players")]
    assert.equal("submenu", players.kind)
    assert.is_false(players.destructive)

    local heal = rows[index_of(m, "heal")]
    assert.equal("toggle", heal.kind)
    assert.is_true(heal.value)

    -- An off toggle must report false, not nil: a renderer drawing [x]/[ ]
    -- has to tell "off" apart from "this row has no toggle state at all".
    local god = rows[index_of(m, "godmode")]
    assert.equal("toggle", god.kind)
    assert.is_false(god.value)

    local spawn = rows[index_of(m, "spawn")]
    assert.equal("action", spawn.kind)
    assert.is_nil(spawn.value)                   -- only toggles carry a value
  end)

  it("set_message surfaces a line through view", function()
    local m = menu.new(spec, {}); m:open()
    assert.is_nil(m:view().message)
    m:set_message("Host only - you are not the session authority")
    assert.equal("Host only - you are not the session authority", m:view().message)
    m:set_message(nil)
    assert.is_nil(m:view().message)
  end)

  it("set_message degrades a non-string instead of erroring", function()
    local m = menu.new(spec, {}); m:open()
    m:set_message(42)
    assert.equal("42", m:view().message)
  end)

  it("the message clears on close, on open and on a page change", function()
    local m = menu.new(spec, {}); m:open()

    m:set_message("player no longer in session")
    m:close()
    assert.is_nil(m.message)

    m:open()
    m:set_message("not available on this game version")
    m:open()
    assert.is_nil(m:view().message)

    m:set_message("stale")
    select_row(m, "players"); m:input("select")   -- into the submenu
    assert.is_nil(m:view().message)

    m:set_message("stale again")
    m:input("back")                                -- back out of the submenu
    assert.is_nil(m:view().message)
  end)

  it("view returns fresh tables a renderer cannot corrupt", function()
    local m = menu.new(spec, {}); m:open()
    local first = m:view()
    assert.are_not.equal(first, m:view())
    assert.are_not.equal(first.rows[1], m:view().rows[1])
    first.rows[1].label = "CLOBBERED"
    first.rows[1].selected = false
    table.remove(first.rows)
    assert.equal(LABELS.spawn, m:view().rows[1].label)
    assert.is_true(m:view().rows[1].selected)
    assert.equal(#spec.items, #m:view().rows)
  end)

  it("entering a submenu resets its cursor to the first row", function()
    local m = menu.new(spec, {}); m:open()
    select_row(m, "players"); m:input("select")
    assert.equal("Players", m:view().title)
    assert.is_true(m:view().rows[1].selected)
  end)
end)
