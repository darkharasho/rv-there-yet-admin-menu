# RV There Yet Admin Menu — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a host-only, hotkey-summonable admin overlay for *RV There Yet?* that spawns items, revives/kills/heals/teleports any player, and warps to checkpoints.

**Architecture:** A RE-UE4SS **Lua** mod (not BepInEx — the game is Unreal Engine 5; see spec). Every call into the engine goes through a single adapter module `lib/ue.lua`, so the menu state machine, config parser, and command dispatch are pure Lua that runs headless under `busted` with a fake adapter. The menu is **mouse-driven**, drawn as rectangles and text from a hook on the game's HUD draw event, with hit-testing done in pure Lua — so layout and click behaviour are unit-tested headless too. Drawing is isolated in `lib/render.lua`, the one file that changes if we switch overlay technology. Actions execute on the host, where the session is authoritative, and replicate to clients; clients need no mod.

**Tech Stack:** Lua 5.4, RE-UE4SS (via `Thunderstore-unreal_shimloader-1.1.7`), `busted` + `luassert` for tests, Thunderstore packaging, GitHub Actions for release.

**Spec:** `docs/superpowers/specs/2026-09-27-admin-menu-spec.md`

## Global Constraints

- Loader dependency string, verbatim in `manifest.json`: `Thunderstore-unreal_shimloader-1.1.7`
- Lua dialect: **Lua 5.4** (UE4SS's embedded interpreter). No LuaJIT-only syntax, no external rocks at runtime.
- Package layout must match the `samlii-MoreRVers` convention exactly: `manifest.json`, `icon.png` (256×256), `README.md` at zip root; `mod/enabled.txt`, `mod/config.ini`, `mod/scripts/main.lua` below it.
- **Every** call into a UE4SS global or engine object is wrapped in `pcall` and the global is `rawget`-checked before use. A UE4SS or game update must degrade the mod to "fewer features + a logged warning", never a crash. This is the `MoreRVers` convention and this community's baseline.
- Host-only: every action checks authority first and refuses with a visible message otherwise.
- The menu must be operable with the **mouse** (hover to highlight, left-click to activate), with keyboard navigation as an equal-footing fallback. Mouse cursor visibility is saved on open and restored on close.
- Thunderstore team: `darkharasho`. Community slug: `rv-there-yet`.
- Publishing follows `~/.claude/templates/thunderstore/thunderstore-publish.sh` on tag push (see global CLAUDE.md).
- No anti-cheat evasion, no detection-avoidance behavior, and the README must state the mod is for private lobbies with consenting players.

## Review Focus

Five things the spec implies but no feature task naturally exercises. Each has its test pinned to the task that owns the code.

1. **Non-host opens the menu.** A client joins a session, presses the hotkey, picks "Kill player 2". Expected: menu opens read-only or refuses with "Host only — you are not the session authority", and no engine write is attempted. → tested in Task 9.
2. **Target player disconnects while their row is selected.** Roster holds a stale controller; the next action dereferences a dead UObject. Expected: the roster revalidates before every action, the row disappears, and the action reports "player no longer in session". → tested in Task 9.
3. **`config.ini` is missing, empty, or has a garbage hotkey (`Hotkey = F27`).** Expected: mod loads, logs a WARN naming the bad key and the fallback, and binds the default hotkey. It must not fail to load. → tested in Task 4.
4. **Hotkey pressed while driving / menu open during input-heavy play.** Expected: opening the menu never blocks vehicle input the player still needs; the toggle key is rebindable via `config.ini` precisely so a colliding default can be moved; and the mouse cursor is shown only while the menu is open and **restored to its previous state on close**, so the mod never leaves a stray cursor over gameplay or eats a click the player aimed at the game. → tested in Task 8.
5. **A game patch renames the pawn or checkpoint class.** Expected: the affected menu page shows "not available on this game version — see UE4SS.log", other pages keep working, and diagnostics name the missing class. → tested in Task 6.

---

### Task 1: Repo skeleton, packaging, and a mod that loads

> **Controller note (pre-flight):** `.gitignore`, `tests/smoke_spec.lua`, `scripts/test.sh` and `scripts/bootstrap-toolchain.sh` already exist on this branch — a working Lua 5.4 + `busted` toolchain was bootstrapped during setup because this machine has no system Lua and no root. **Amend** those files; do not overwrite them. Run tests with `./scripts/test.sh`, and make any `.busted` config you add compatible with that wrapper.

**Files:**
- Create: `manifest.json`, `icon.png`, `README.md`, `CHANGELOG.md`, `.gitignore`
- Create: `mod/enabled.txt`, `mod/config.ini`, `mod/scripts/main.lua`
- Create: `scripts/build-package.sh`
- Create: `.busted`, `tests/smoke_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `scripts/build-package.sh` → `dist/RVAdminMenu-<version>.zip`; `busted` runs specs in `tests/`.

- [ ] **Step 1: Write the failing smoke test**

`tests/smoke_spec.lua`:
```lua
describe("package layout", function()
  it("declares the shimloader dependency", function()
    local f = assert(io.open("manifest.json", "r"))
    local body = f:read("a"); f:close()
    assert.truthy(body:find("Thunderstore%-unreal_shimloader%-1%.1%.7"))
  end)
end)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `busted tests/smoke_spec.lua`
Expected: FAIL — `manifest.json` does not exist.

- [ ] **Step 3: Create the package files**

`manifest.json`:
```json
{
    "name": "RVAdminMenu",
    "author": "darkharasho",
    "version_number": "0.1.0",
    "description": "Host-side admin menu: spawn items, revive/kill/heal/teleport players, warp to checkpoints",
    "website_url": "https://github.com/darkharasho/rv-there-yet-admin-menu",
    "dependencies": [
        "Thunderstore-unreal_shimloader-1.1.7"
    ]
}
```

`mod/enabled.txt`: empty file (its presence is what enables the mod).

`mod/scripts/main.lua`:
```lua
local MOD_NAME, MOD_VERSION = "RVAdminMenu", "0.1.0"
print(string.format("[%s] v%s loaded\n", MOD_NAME, MOD_VERSION))
```

`.busted`:
```lua
return { default = { ROOT = { "tests" }, pattern = "_spec" } }
```

`.gitignore`:
```
dist/
*.zip
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `busted`
Expected: PASS, 1 success.

- [ ] **Step 5: Write the package builder**

`scripts/build-package.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -oP '"version_number":\s*"\K[^"]+' manifest.json)
out="dist/RVAdminMenu-${version}.zip"
mkdir -p dist && rm -f "$out"
zip -r "$out" manifest.json icon.png README.md mod/ -x '*.DS_Store'
echo "built $out"
```

Make it executable: `chmod +x scripts/build-package.sh`

- [ ] **Step 6: Build the zip and verify its contents**

Run: `scripts/build-package.sh && unzip -l dist/RVAdminMenu-0.1.0.zip`
Expected: `manifest.json`, `icon.png`, `README.md`, `mod/enabled.txt`, `mod/config.ini`, `mod/scripts/main.lua` at the paths above.

- [ ] **Step 7: Load it in-game once, by hand**

Install the zip through r2modman into an RV There Yet profile alongside `unreal_shimloader`, launch, then check `UE4SS.log` for `[RVAdminMenu] v0.1.0 loaded`.
Expected: the line is present. If it is not, nothing later in this plan can be verified in-game — stop and fix the packaging first.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: UE4SS lua mod skeleton with thunderstore packaging"
```

---

### Task 2: Recon — dump the game's object model

This task produces **data, not features**. Tasks 6 and 9–12 cannot be written correctly without it; do not guess class names.

**Files:**
- Create: `tools/dump-game-objects.lua`
- Create: `docs/game-objects.md`

**Interfaces:**
- Consumes: Task 1's working install.
- Produces: `docs/game-objects.md` — the canonical list of class and property names every later task reads. Later tasks refer to it as "the recon doc".

- [ ] **Step 1: Write the dump script**

`tools/dump-game-objects.lua` — install it as a temporary UE4SS mod. It binds F9 and, on press, logs:
```lua
local function dump(label, className)
  local ok, list = pcall(FindAllOf, className)
  if not ok or type(list) ~= "table" then
    print(string.format("[recon] %s (%s): none\n", label, className)); return
  end
  for _, o in ipairs(list) do
    local okn, n = pcall(function() return o:GetFullName() end)
    print(string.format("[recon] %s: %s\n", label, okn and n or "<unnamed>"))
  end
end

RegisterKeyBind(Key.F9, function()
  ExecuteInGameThread(function()
    dump("controller", "PlayerController")
    dump("playerstate", "PlayerState")
    dump("pawn",        "Pawn")
    dump("character",   "Character")
    dump("gamemode",    "GameModeBase")
    dump("gamestate",   "GameStateBase")
    dump("gamesession", "GameSession")
    dump("hud",         "HUD")
    DumpAllObjects()   -- full UObject listing, written next to UE4SS.dll
  end)
end)
```

- [ ] **Step 2: Run it in a live 2-player session**

Host a session with a second player connected, press F9, and collect `UE4SS.log` plus the `ObjectDump.txt` that `DumpAllObjects()` writes.

- [ ] **Step 3: Answer these questions in `docs/game-objects.md`**

Write one section per question, each with the exact `/Script/...` or `/Game/...` path and the property names, quoted from the dump:

1. The player **pawn/character class** and its health-bearing properties (health, max health, downed/dead flag).
2. The **player controller** and **player state** classes, and which property holds the display name.
3. The function(s) that run on **death** and on **revive** — grep the dump for `Revive`, `Down`, `Die`, `Respawn`, `Damage`.
4. The **checkpoint** actor class — grep for `Checkpoint`, `Respawn`, `Spawn`, `Milestone` — and how a checkpoint identifies itself (index? name? tag?).
5. The **spawnable item** base class — grep for `Pickup`, `Item`, `Consumable`, `Prop` — and the set of concrete Blueprint classes under `/Game/`.
6. Whether the game exposes a **CheatManager** (the loader ships `CheatManagerEnablerMod` enabled), and which of `God`/`Teleport`/`Summon` actually work.
7. How the host distinguishes itself: which property or function reports **authority** (`HasAuthority`, `GetLocalRole`, `IsServer`).
8. **Is there an `AHUD` subclass, and does its draw event fire?** Grep the dump for `HUD`. Record the class path, and confirm by hooking it — the menu's whole rendering approach depends on this:
   ```lua
   RegisterHook("/Script/Engine.HUD:ReceiveDrawHUD", function(hud, w, h)
     print(string.format("[recon] ReceiveDrawHUD %sx%s\n", tostring(w:get()), tostring(h:get())))
   end)
   ```
   If that fires, also confirm `DrawRect` and `DrawText` are callable on the HUD object from inside the hook. **If it never fires, stop and report** — Task 8 takes its fallback path and the plan needs revisiting.
9. **Mouse plumbing on the local `PlayerController`:** confirm `bShowMouseCursor` is writable, and which of `GetMousePosition` / `WasInputKeyJustPressed` / `IsInputKeyDown` are callable. Record the current value of `bShowMouseCursor` during normal play — Task 8 must restore it.

- [ ] **Step 4: Commit the findings**

```bash
git add tools/dump-game-objects.lua docs/game-objects.md
git commit -m "docs: game object recon for RV There Yet"
```

---

### Task 3: Leveled logging

**Files:**
- Create: `mod/scripts/lib/log.lua`
- Test: `tests/log_spec.lua`

**Interfaces:**
- Produces: `log.new(opts) -> logger` with `logger:debug(msg)`, `:info(msg)`, `:warn(msg)`, `:error(msg)`, and `logger:set_level(name)`. `opts = { name = string, level = string, sink = function(string) }`; `sink` defaults to `print`.

- [ ] **Step 1: Write the failing test**

`tests/log_spec.lua`:
```lua
local log = require("mod.scripts.lib.log")

describe("log", function()
  local lines, logger
  before_each(function()
    lines = {}
    logger = log.new{ name = "T", level = "WARN", sink = function(s) lines[#lines+1] = s end }
  end)

  it("suppresses messages below the level", function()
    logger:info("quiet")
    assert.equal(0, #lines)
  end)

  it("emits messages at or above the level", function()
    logger:error("loud")
    assert.equal(1, #lines)
    assert.truthy(lines[1]:find("%[T%]"))
    assert.truthy(lines[1]:find("ERROR"))
    assert.truthy(lines[1]:find("loud"))
  end)

  it("falls back to INFO for an unknown level name", function()
    local l = log.new{ name = "T", level = "BANANA", sink = function(s) lines[#lines+1] = s end }
    l:info("shown"); l:debug("hidden")
    assert.equal(1, #lines)
  end)
end)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `busted tests/log_spec.lua`
Expected: FAIL — module `mod.scripts.lib.log` not found.

- [ ] **Step 3: Implement**

`mod/scripts/lib/log.lua`:
```lua
local M = {}
local LEVELS = { DEBUG = 10, INFO = 20, WARN = 30, ERROR = 40 }

local Logger = {}
Logger.__index = Logger

function Logger:set_level(name)
  self.level = LEVELS[tostring(name):upper()] or LEVELS.INFO
end

local function emit(self, level, msg)
  if LEVELS[level] < self.level then return end
  local ok, stamp = pcall(os.date, "%H:%M:%S")
  self.sink(string.format("[%s] [%s] [%s] %s\n",
    ok and stamp or "--:--:--", self.name, level, tostring(msg)))
end

function Logger:debug(m) emit(self, "DEBUG", m) end
function Logger:info(m)  emit(self, "INFO",  m) end
function Logger:warn(m)  emit(self, "WARN",  m) end
function Logger:error(m) emit(self, "ERROR", m) end

function M.new(opts)
  opts = opts or {}
  local self = setmetatable({
    name = opts.name or "RVAdminMenu",
    sink = opts.sink or print,
  }, Logger)
  self:set_level(opts.level)
  return self
end

return M
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/log_spec.lua`
Expected: PASS, 3 successes.

- [ ] **Step 5: Commit**

```bash
git add mod/scripts/lib/log.lua tests/log_spec.lua
git commit -m "feat: leveled logger"
```

---

### Task 4: Config parsing and hotkey resolution

Owns Review Focus item 3.

**Files:**
- Create: `mod/scripts/lib/config.lua`
- Modify: `mod/config.ini`
- Test: `tests/config_spec.lua`

**Interfaces:**
- Consumes: `log` from Task 3.
- Produces:
  - `config.parse_ini(text) -> table` — lowercased keys, string values.
  - `config.resolve(ini, logger) -> cfg` where `cfg = { hotkey = string, hotkey_valid = boolean, log_level = string, confirm_destructive = boolean, heal_amount = number }`. `hotkey` is always a name that exists in `config.KEY_NAMES`.
  - `config.KEY_NAMES` — the set of key names this mod accepts, matching UE4SS's `Key` table (`"F1".."F12"`, `"INSERT"`, `"HOME"`, `"END"`, `"DELETE"`, `"PAGE_UP"`, `"PAGE_DOWN"`).

- [ ] **Step 1: Write the failing test**

`tests/config_spec.lua`:
```lua
local config = require("mod.scripts.lib.config")
local log = require("mod.scripts.lib.log")

local function quiet(collected)
  return log.new{ name = "T", level = "DEBUG", sink = function(s) collected[#collected+1] = s end }
end

describe("config", function()
  it("parses keys case-insensitively and skips comments", function()
    local t = config.parse_ini("; note\nHotkey = F4\n# other\nHealAmount=50\n")
    assert.equal("F4", t.hotkey)
    assert.equal("50", t.healamount)
  end)

  it("uses defaults when the ini is empty", function()
    local cfg = config.resolve({}, quiet({}))
    assert.equal("F3", cfg.hotkey)
    assert.is_true(cfg.hotkey_valid)
    assert.is_true(cfg.confirm_destructive)
  end)

  it("falls back to the default hotkey and warns on a bad key name", function()
    local lines = {}
    local cfg = config.resolve({ hotkey = "F27" }, quiet(lines))
    assert.equal("F3", cfg.hotkey)
    assert.is_false(cfg.hotkey_valid)
    local joined = table.concat(lines)
    assert.truthy(joined:find("WARN"))
    assert.truthy(joined:find("F27"))
    assert.truthy(joined:find("F3"))
  end)

  it("clamps heal amount into 1..1000", function()
    assert.equal(1000, config.resolve({ healamount = "99999" }, quiet({})).heal_amount)
    assert.equal(1, config.resolve({ healamount = "-5" }, quiet({})).heal_amount)
  end)

  it("reads booleans in the forms the community uses", function()
    for _, v in ipairs({ "0", "false", "no", "off" }) do
      assert.is_false(config.resolve({ confirmdestructive = v }, quiet({})).confirm_destructive)
    end
  end)
end)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `busted tests/config_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `mod/scripts/lib/config.lua`**

`parse_ini` reads `key = value` lines, trimming whitespace, skipping blank lines, `;`/`#` comments and `[section]` headers, lowercasing keys. `resolve` applies these defaults and validations:

| ini key | field | default | validation |
|---|---|---|---|
| `hotkey` | `hotkey` | `"F3"` | must be in `KEY_NAMES`; else default + WARN naming both the bad value and the fallback, and set `hotkey_valid = false` |
| `loglevel` | `log_level` | `"INFO"` | uppercased; unknown values are left for `log.new` to default |
| `confirmdestructive` | `confirm_destructive` | `true` | `1/true/yes/on` → true, `0/false/no/off` → false, anything else → default |
| `healamount` | `heal_amount` | `100` | `tonumber`, floored, clamped to `1..1000` |

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/config_spec.lua`
Expected: PASS, 7 successes.

- [ ] **Step 5: Write the shipped `mod/config.ini`**

Document every key above with its default, its range, and the note that the hotkey must be one of `KEY_NAMES` — follow the commented style of `MoreRVers`' `config.ini`.

- [ ] **Step 6: Commit**

```bash
git add mod/scripts/lib/config.lua mod/config.ini tests/config_spec.lua
git commit -m "feat: config parsing with validated hotkey"
```

---

### Task 5: The engine adapter seam

Every later task talks to the game only through this module. It is the reason the rest is testable.

**Files:**
- Create: `mod/scripts/lib/ue.lua`
- Create: `tests/support/fake_ue.lua`
- Test: `tests/ue_spec.lua`

**Interfaces:**
- Produces `ue.new(logger) -> adapter` with exactly this surface, every method `pcall`-guarded and returning `value, err`:
  - `adapter:available() -> boolean` — are the UE4SS globals present at all
  - `adapter:find_all(class_name) -> table` (empty table, never nil)
  - `adapter:find_first(class_name) -> object|nil`
  - `adapter:get(obj, prop) -> value|nil, err`
  - `adapter:set(obj, prop, value) -> boolean, err` — reads back and reports whether the write stuck
  - `adapter:call(obj, fn_name, ...) -> value|nil, err`
  - `adapter:is_valid(obj) -> boolean`
  - `adapter:class_of(obj) -> string`
  - `adapter:in_game_thread(fn)` — routes through `ExecuteInGameThread` when present, else calls directly
  - `adapter:bind_key(key_name, fn) -> boolean`
  - `adapter:on_hook(signature, fn) -> boolean`
  - `adapter:mouse_state() -> { x = number, y = number, down = boolean }|nil` — the local player's cursor position and left-button state, read from the PlayerController functions named in the recon doc. Returns `nil` (never a partial table) when the controller or any function is unavailable, so callers have exactly one failure case to handle.
  - `adapter:set_cursor_visible(visible) -> boolean|nil` — writes `bShowMouseCursor` and returns the **previous** value, so the caller can restore it; `nil` if the write failed.
- `tests/support/fake_ue.lua` implements the same surface over plain Lua tables, with `fake.objects[class_name] = { ... }`, a `fake.calls` log, and `fake.fail_on = { ["set:Health"] = true }` to simulate rejected writes.

- [ ] **Step 1: Write the failing test**

`tests/ue_spec.lua` drives `ue.new` against a stubbed `_G` and asserts:
```lua
it("returns an empty table when FindAllOf is absent", function()
  local a = ue.new(logger)          -- no UE4SS globals in _G
  assert.same({}, a:find_all("Pawn"))
  assert.is_false(a:available())
end)

it("reports a write that does not stick", function()
  _G.FindAllOf = function() return {} end
  local obj = setmetatable({}, { __newindex = function() end, __index = function() return 5 end })
  local a = ue.new(logger)
  local ok, err = a:set(obj, "Health", 100)
  assert.is_false(ok)
  assert.truthy(err:find("did not stick"))
end)

it("never propagates an engine error", function()
  local obj = setmetatable({}, { __index = function() error("engine exploded") end })
  local a = ue.new(logger)
  local v, err = a:get(obj, "Health")
  assert.is_nil(v)
  assert.truthy(err)
end)
```

- [ ] **Step 2: Run it and watch it fail**

Run: `busted tests/ue_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `ue.lua` and `fake_ue.lua`**

Look up every UE4SS global with `rawget(_G, name)` and type-check it before calling, exactly as `MoreRVers` does. `set` writes, reads back, and only returns `true` when the read-back equals the written value.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/ue_spec.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mod/scripts/lib/ue.lua tests/support/fake_ue.lua tests/ue_spec.lua
git commit -m "feat: pcall-guarded engine adapter seam"
```

---

### Task 6: Session model — authority, roster, and capability probing

Owns Review Focus items 1, 2 and 5.

**Files:**
- Create: `mod/scripts/lib/session.lua`
- Test: `tests/session_spec.lua`

**Interfaces:**
- Consumes: `ue` adapter (Task 5), recon doc (Task 2) for the real class and property names.
- Produces:
  - `session.new(adapter, names, logger) -> s`, where `names` is the class/property table filled in from the recon doc.
  - `s:is_host() -> boolean`
  - `s:players() -> { { id, name, controller, pawn, alive, health, max_health }, ... }` — rebuilt from the engine on every call, skipping objects that fail `is_valid`
  - `s:player_by_id(id) -> player|nil`
  - `s:capabilities() -> { players = bool, checkpoints = bool, items = bool }` — false when the recon class is missing on this game build
  - `s:missing_report() -> string` — names the classes that could not be found, for the "not available on this game version" message

- [ ] **Step 1: Write the failing tests**

`tests/session_spec.lua`, using `fake_ue`:
```lua
it("reports not-host when authority is false", function()
  fake.objects.PlayerController = { { HasAuthority = function() return false end } }
  assert.is_false(session.new(fake, names, logger):is_host())
end)

it("drops a player whose controller went invalid", function()
  local s = session.new(fake, names, logger)
  assert.equal(2, #s:players())
  fake:invalidate(fake.objects.PlayerController[2])
  assert.equal(1, #s:players())          -- revalidated, not cached
end)

it("marks a capability unavailable when its class is missing", function()
  fake.objects.BP_Checkpoint_C = nil
  local s = session.new(fake, names, logger)
  local caps = s:capabilities()
  assert.is_false(caps.checkpoints)
  assert.is_true(caps.players)
  assert.truthy(s:missing_report():find("Checkpoint"))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/session_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `session.lua`**

`players()` enumerates controllers via `adapter:find_all(names.controller)`, resolves each one's pawn and player state, and reads `names.health` / `names.max_health` / `names.alive`. No caching of engine objects between calls — that is what makes a mid-session disconnect safe.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/session_spec.lua`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add mod/scripts/lib/session.lua tests/session_spec.lua
git commit -m "feat: session roster with authority and capability probing"
```

---

### Task 7: Menu state machine (pure)

The heart of the UI, with no engine dependency at all.

**Files:**
- Create: `mod/scripts/lib/menu.lua`
- Test: `tests/menu_spec.lua`

**Interfaces:**
- Produces:
  - `menu.new(spec, opts) -> m` where `opts = { confirm_destructive = bool }` and `spec` is a tree of pages: `{ id, title, items = { { id, label, kind = "action"|"submenu"|"toggle", target, destructive = bool } } }`
  - `m:open()`, `m:close()`, `m:is_open() -> boolean`
  - `m:input(event) -> command|nil` for `event` in `"up"|"down"|"select"|"back"|"cancel"`. Returns `{ action = id, target = id }` only when an action fires, otherwise `nil`.
  - `m:hover(index)` — moves the cursor to a row by 1-based index, ignoring out-of-range values. This is the **only** entry point the mouse needs: the renderer turns a pixel position into a row index and calls this, so `menu.lua` stays engine-free and knows nothing about pixels. A mouse click is then exactly `m:hover(i)` followed by `m:input("select")`, which means clicking a destructive row goes through the identical confirmation flow as selecting it by keyboard.
  - `m:view() -> { title, rows = { { label, selected = bool } }, prompt = string|nil }` — everything the renderer needs and nothing more
  - `m:set_pending(cmd)` / confirm flow: selecting a `destructive` item when `confirm_destructive` is on sets `view().prompt`, and only a second `"select"` emits the command; `"cancel"` clears it

- [ ] **Step 1: Write the failing tests**

`tests/menu_spec.lua`:
```lua
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
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/menu_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `menu.lua`** as a page stack with a per-page cursor and a single `pending` slot. `hover` clamps by rejecting anything outside `1..#rows` rather than clamping into range — a mouse outside the list must not drag the selection to an edge row. Changing the cursor clears any `pending` confirmation, so moving off a destructive row and clicking elsewhere cannot fire the confirmed action.

`index_of(m, id)` and `select_row(m, id)` are test helpers at the top of the spec file that walk `m:view().rows` to find a row by label.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/menu_spec.lua`
Expected: PASS, 7 successes.

- [ ] **Step 5: Commit**

```bash
git add mod/scripts/lib/menu.lua tests/menu_spec.lua
git commit -m "feat: pure menu state machine with destructive-action confirmation"
```

---

### Task 8: Rendering, mouse input, and the hotkey

Owns Review Focus item 4. **Depends on Task 2 recon questions 8 and 9.** If the recon found no working `AHUD` draw event, stop and escalate before writing this task — the fallback ladder is in the spec.

The trick that makes this testable: layout and hit-testing are pure arithmetic over `m:view()`. They live in functions that never touch the engine, so the entire mouse behaviour is unit-tested headless. Only `draw` talks to the HUD.

**Files:**
- Create: `mod/scripts/lib/render.lua`
- Modify: `mod/scripts/main.lua`
- Test: `tests/render_spec.lua`

**Interfaces:**
- Consumes: `m:view()` and `m:hover(i)` (Task 7), `ue` adapter (Task 5), `cfg.hotkey` (Task 4).
- Produces:
  - `render.new(adapter, logger, opts) -> r` where `opts = { x = number, y = number, row_h = number, width = number }`, all with defaults (`x = 60`, `y = 60`, `row_h = 22`, `width = 320`)
  - `r:layout(view) -> layout` — pure. Returns
    `{ x, y, w, h, title = { x, y, text }, rows = { { index, label, selected, x, y, w, h } }, prompt = { x, y, text } | nil }`.
    Rows are laid out top-down below the title; the prompt, when present, sits below the last row and is **not** a hit target.
  - `r:hit(layout, mx, my) -> index|nil` — pure point-in-rect test over `layout.rows`, returning the 1-based row index or `nil` when the cursor is outside every row.
  - `r:draw(hud, layout)` — the only engine-touching function: one `DrawRect` for the panel, one per row (highlighted for `selected`), and a `DrawText` per label.

- [ ] **Step 1: Write the failing tests**

`tests/render_spec.lua`:
```lua
local render = require("lib.render")
local r = render.new(fake, logger, { x = 100, y = 50, row_h = 20, width = 200 })

local view = {
  title = "Players",
  prompt = "Kill Bob? (click again to confirm)",
  rows = { { label = "Alice", selected = false }, { label = "Bob", selected = true } },
}

it("lays rows out top-down inside the panel", function()
  local l = r:layout(view)
  assert.equal(2, #l.rows)
  assert.equal(1, l.rows[1].index)
  assert.equal("Alice", l.rows[1].label)
  assert.is_true(l.rows[2].y > l.rows[1].y)
  assert.is_true(l.rows[2].selected)
  -- every row sits within the panel
  for _, row in ipairs(l.rows) do
    assert.is_true(row.x >= l.x and row.x + row.w <= l.x + l.w)
    assert.is_true(row.y >= l.y and row.y + row.h <= l.y + l.h)
  end
end)

it("hit-tests a point inside a row to that row's index", function()
  local l = r:layout(view)
  local row = l.rows[2]
  assert.equal(2, r:hit(l, row.x + 1, row.y + 1))
  assert.equal(2, r:hit(l, row.x + row.w - 1, row.y + row.h - 1))
end)

it("returns nil for points outside every row", function()
  local l = r:layout(view)
  assert.is_nil(r:hit(l, l.x - 5, l.y - 5))          -- outside the panel
  assert.is_nil(r:hit(l, l.x + 5, l.y + l.h + 50))   -- below the panel
  assert.is_nil(r:hit(l, l.rows[1].x + 1, l.title.y))-- on the title, not a row
end)

it("does not make the prompt clickable", function()
  local l = r:layout(view)
  assert.is_nil(r:hit(l, l.prompt.x + 1, l.prompt.y + 1))
end)

it("renders an empty roster without error and hits nothing", function()
  local l = r:layout{ title = "Players", rows = {} }
  assert.equal(0, #l.rows)
  assert.is_nil(r:hit(l, l.x + 1, l.y + 1))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/render_spec.lua`
Expected: FAIL — module `lib.render` not found.

- [ ] **Step 3: Implement `layout` and `hit` as pure functions**

No engine calls in either. `hit` is `mx >= row.x and mx < row.x + row.w and my >= row.y and my < row.y + row.h` over the row list — half-open intervals so adjacent rows never both match.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/render_spec.lua`
Expected: PASS, 5 successes.

- [ ] **Step 5: Implement `draw` and wire it to the HUD hook in `main.lua`**

Use the exact HUD class path from the recon doc. Everything inside the hook is `pcall`-wrapped: a throwing draw hook fires every frame and would flood the log and stutter the game, so on the first failure log one ERROR, set a `render_disabled` flag, and stop drawing.

```lua
adapter:on_hook(HUD_DRAW_PATH, function(hud)
  if not m:is_open() or render_disabled then return end
  local ok, err = pcall(function()
    local layout = r:layout(m:view())
    r:draw(hud:get(), layout)
  end)
  if not ok then
    logger:error("draw failed, disabling overlay: " .. tostring(err))
    render_disabled = true
  end
end)
```

- [ ] **Step 6: Wire mouse input**

In the same hook, after drawing: read the cursor via `adapter:mouse_state()`, call `r:hit`, and feed the result to the menu. Track the previous button state so a held button fires once, not every frame — `clicked` is "down now, up last frame".

```lua
local ms = adapter:mouse_state()
if not ms then return end          -- no cursor data: keyboard still works
local clicked = ms.down and not was_down
was_down = ms.down
local i = r:hit(layout, ms.x, ms.y)
if i then m:hover(i) end
if i and clicked then m:input("select") end
```

Consume clicks only when `i` is non-nil — a click outside the panel belongs to the game, not the mod.

- [ ] **Step 7: Show and restore the cursor around open/close**

On open, call `adapter:set_cursor_visible(true)` and keep its return value — the previous state. On close, write that recorded value back with `adapter:set_cursor_visible(prev)` — never an unconditional `false`. Also restore it if the menu is force-closed by a map change, so a level transition cannot strand the cursor on.

- [ ] **Step 8: Bind the hotkey and the keyboard fallback in `main.lua`**

`main.lua` reads `config.ini`, builds logger → adapter → session → menu → renderer, then binds `cfg.hotkey` to toggle the menu. Navigation keys (arrows, enter, escape) are handled **only while the menu is open** and ignored otherwise, so the mod never eats input during driving.

- [ ] **Step 9: Verify in-game**

1. Open the menu while parked. Hover rows with the mouse — the highlight follows the cursor. Click a row — it activates. Click a destructive row — it prompts, and a second click confirms.
2. Close the menu, then drive and use every vehicle control. Expected: no input swallowed, and the mouse cursor is back to exactly how it was before.
3. Click outside the panel with the menu open. Expected: the menu does not react.
4. Set `Hotkey = F4` in `config.ini`, restart, and confirm the new key opens the menu.

- [ ] **Step 10: Commit**

```bash
git add mod/scripts/lib/render.lua mod/scripts/main.lua tests/render_spec.lua
git commit -m "feat: mouse-driven menu overlay with rebindable hotkey"
```

---

### Task 9: Player actions — revive, kill, heal

Owns Review Focus items 1 and 2.

**Files:**
- Create: `mod/scripts/lib/actions.lua`
- Modify: `mod/scripts/main.lua`
- Test: `tests/actions_spec.lua`

**Interfaces:**
- Consumes: `session` (Task 6), `ue` adapter (Task 5), recon doc (Task 2).
- Produces: `actions.new(adapter, session, names, cfg, logger) -> a` with `a:revive(id)`, `a:kill(id)`, `a:heal(id)`, each returning `ok, message`. `message` is always human-readable and always shown in the menu.

- [ ] **Step 1: Write the failing tests**

```lua
it("refuses every action when not the host", function()
  fake:set_authority(false)
  local ok, msg = a:kill("p2")
  assert.is_false(ok)
  assert.truthy(msg:find("Host only"))
  assert.equal(0, #fake.calls)             -- nothing was attempted
end)

it("reports a player who left rather than touching a dead object", function()
  fake:invalidate(fake.objects.PlayerController[2])
  local ok, msg = a:heal("p2")
  assert.is_false(ok)
  assert.truthy(msg:find("no longer in session"))
end)

it("heals up to max health, never past it", function()
  fake:set_health("p2", 10, 100)
  assert.is_true(a:heal("p2"))
  assert.equal(100, fake:health("p2"))
end)

it("surfaces a write that the engine rejected", function()
  fake.fail_on["set:Health"] = true
  local ok, msg = a:heal("p2")
  assert.is_false(ok)
  assert.truthy(msg:find("did not apply"))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/actions_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Every public method starts with `if not self.session:is_host() then return false, "Host only — you are not the session authority" end`, then re-resolves the target through `session:player_by_id(id)`. Prefer calling the game's own revive/kill function found in recon step 3 over writing the health property directly; fall back to the property write when no function exists.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/actions_spec.lua`
Expected: PASS, 4 successes.

- [ ] **Step 5: Verify in a live 2-player session**

Kill, then revive, then heal the second player. Confirm the second player's own screen reflects each change with the mod **not** installed on their machine.

- [ ] **Step 6: Commit**

```bash
git add mod/scripts/lib/actions.lua mod/scripts/main.lua tests/actions_spec.lua
git commit -m "feat: host-authoritative revive, kill and heal"
```

---

### Task 10: Teleport

**Files:**
- Modify: `mod/scripts/lib/actions.lua`
- Test: `tests/actions_spec.lua`

**Interfaces:**
- Produces: `a:teleport(from_id, to_id)` and `a:teleport_to_point(id, {x,y,z})`, returning `ok, message`.

- [ ] **Step 1: Write the failing tests**

```lua
it("moves the pawn to the destination pawn's location", function()
  fake:set_location("p2", { x = 0, y = 0, z = 0 })
  fake:set_location("p1", { x = 100, y = 200, z = 30 })
  assert.is_true(a:teleport("p2", "p1"))
  assert.same({ x = 100, y = 200, z = 30 }, fake:location("p2"))
end)

it("refuses to teleport a player onto themselves", function()
  local ok, msg = a:teleport("p2", "p2")
  assert.is_false(ok)
  assert.truthy(msg:find("same player"))
end)

it("forces a client position correction for a remote pawn", function()
  a:teleport("p2", "p1")
  assert.truthy(fake:called("ClientSetLocation") or fake:called("K2_TeleportTo"))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/actions_spec.lua -f teleport`
Expected: FAIL.

- [ ] **Step 3: Implement**

A plain `SetActorLocation` on a remote player's pawn is reverted by that client's next `CharacterMovementComponent` update. Teleport must go through `K2_TeleportTo` on the pawn **and** `ClientSetLocation` on the controller (whichever of the two the recon doc confirms exists), so the owning client accepts the correction. Verify this in-game before believing the unit test.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/actions_spec.lua`
Expected: PASS.

- [ ] **Step 5: Verify in a live 2-player session that the remote player stays moved**

Teleport the remote player, then have them walk. Expected: they stay at the new location; they do not snap back.

- [ ] **Step 6: Commit**

```bash
git add mod/scripts/lib/actions.lua tests/actions_spec.lua
git commit -m "feat: teleport players with client position correction"
```

---

### Task 11: Item spawning

**Files:**
- Create: `mod/scripts/lib/catalog.lua`
- Modify: `mod/scripts/lib/actions.lua`
- Test: `tests/catalog_spec.lua`

**Interfaces:**
- Produces:
  - `catalog.items(adapter, names) -> { { id, label, class_path }, ... }` — discovered at runtime from the item base class in the recon doc, sorted by label
  - `catalog.filter(list, query) -> list` — case-insensitive substring match
  - `a:spawn_item(class_path, id)` — spawns in front of the given player, returning `ok, message`

- [ ] **Step 1: Write the failing tests**

```lua
it("sorts discovered items by label", function()
  local list = catalog.items(fake, names)
  assert.equal("Battery", list[1].label)
end)

it("filters case-insensitively", function()
  assert.equal(1, #catalog.filter(catalog.items(fake, names), "batt"))
end)

it("returns an empty list, not nil, when the base class is missing", function()
  fake.objects[names.item_base] = nil
  assert.same({}, catalog.items(fake, names))
end)

it("refuses to spawn an unknown class path", function()
  local ok, msg = a:spawn_item("/Game/Nope.Nope_C", "p1")
  assert.is_false(ok)
  assert.truthy(msg:find("unknown item"))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/catalog_spec.lua`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

Discover classes rather than hardcoding a list, so a game update adds items for free. Spawn at the requesting player's location plus a forward offset so the item is reachable and does not spawn inside geometry. Validate `class_path` against the discovered catalog before spawning.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted tests/catalog_spec.lua`
Expected: PASS, 4 successes.

- [ ] **Step 5: Verify in-game that a spawned item is visible and pickable by a non-host player**

- [ ] **Step 6: Commit**

```bash
git add mod/scripts/lib/catalog.lua mod/scripts/lib/actions.lua tests/catalog_spec.lua
git commit -m "feat: runtime item catalog and spawning"
```

---

### Task 12: Checkpoint warp

**Files:**
- Modify: `mod/scripts/lib/catalog.lua`, `mod/scripts/lib/actions.lua`
- Test: `tests/catalog_spec.lua`

**Interfaces:**
- Produces: `catalog.checkpoints(adapter, names) -> { { id, label, location }, ... }` in route order, and `a:warp_to_checkpoint(checkpoint_id, player_id)`.

- [ ] **Step 1: Write the failing tests**

```lua
it("lists checkpoints in route order, not discovery order", function()
  local cps = catalog.checkpoints(fake, names)
  assert.same({ "cp1", "cp2", "cp3" }, ids_of(cps))
end)

it("says so when the level has no checkpoints loaded", function()
  fake.objects[names.checkpoint] = {}
  local ok, msg = a:warp_to_checkpoint("cp1", "p1")
  assert.is_false(ok)
  assert.truthy(msg:find("no checkpoints"))
end)
```

- [ ] **Step 2: Run them and watch them fail**

Run: `busted tests/catalog_spec.lua -f checkpoint`
Expected: FAIL.

- [ ] **Step 3: Implement**, ordering by whatever index/name property the recon doc found on the checkpoint actor, and reusing Task 10's teleport path for the actual move.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `busted`
Expected: PASS, all specs.

- [ ] **Step 5: Verify in-game that warping the whole party to a later checkpoint works and does not break the RV's state**

- [ ] **Step 6: Commit**

```bash
git add mod/scripts/lib/catalog.lua mod/scripts/lib/actions.lua tests/catalog_spec.lua
git commit -m "feat: checkpoint listing and warp"
```

---

### Task 13: Release automation

**Files:**
- Create: `.github/workflows/release.yml`, `scripts/thunderstore-publish.sh`
- Modify: `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Copy the publish script**

```bash
cp ~/.claude/templates/thunderstore/thunderstore-publish.sh scripts/
chmod +x scripts/thunderstore-publish.sh
```

- [ ] **Step 2: Write the tag-triggered workflow**

`.github/workflows/release.yml` runs on `push: tags: ['v*']`, runs `busted`, runs `scripts/build-package.sh`, then:
```yaml
      - name: Publish to Thunderstore
        run: scripts/thunderstore-publish.sh dist/RVAdminMenu-${VERSION}.zip --community rv-there-yet
        env:
          THUNDERSTORE_TOKEN: ${{ secrets.THUNDERSTORE_TOKEN }}
```

- [ ] **Step 3: Set the repo secret without printing it**

```bash
( eval "$(grep '^export THUNDERSTORE_ACCESS_TOKEN=' ~/.bashrc)"; \
  printf %s "$THUNDERSTORE_ACCESS_TOKEN" | gh secret set THUNDERSTORE_TOKEN -R darkharasho/rv-there-yet-admin-menu )
```

- [ ] **Step 4: Write the README**

Cover: what it does, that it is **host-only** and clients need nothing installed, install via r2modman/Gale, every `config.ini` key, the default `F3` hotkey, and an explicit line that this is for private lobbies with consenting players.

- [ ] **Step 5: Verify the workflow on a dry run before tagging**

Run: `act -j release` or push a `v0.1.0-rc1` tag to a fork.
Expected: the zip builds and the publish step reports it would upload. **A published Thunderstore version can never be replaced** — confirm the zip is right before tagging for real.

- [ ] **Step 6: Commit**

```bash
git add .github scripts README.md CHANGELOG.md
git commit -m "ci: thunderstore release on tag push"
```
