-- Everything the menu can DO to the game. The engine adapter (ue.lua, or
-- tests/support/fake_ue.lua) is injected, so this module is testable
-- headless. Every engine call goes through adapter:call / :get, which are
-- pcall-guarded; a failed action returns a short message (shown in the
-- menu) and is logged. Nothing here throws into a key-bind callback.
--
-- Engine facts come from docs/game-objects.md and the CXXHeaderDump.
-- Anything marked GUESS has not been seen working in a live session.
local M = {}

local Actions = {}
Actions.__index = Actions

-- Struct field names carry Blueprint GUID suffixes; exact, from the dump.
local GUID = "_42A87BC046D21D82BBBC0E856286E2CD"
local F_RESULTS = "DamageResults_3" .. GUID
local F_TYPE = "DamageType_3" .. GUID
local F_DAMAGE = "Damage_7_F3292EDF44790F4AED9654BACA71838A"
local F_SHIELD = "MaxVehicleShieldConsumption_10_E95C0831458EF361CE55AF89624199AE"
local F_SKIP = "SkipVehicleShield_12_17FC8070442367387C3CBFB05060541B"

local RING_SPACING = 120   -- units between neighbouring teleported players
local RING_LIFT = 50       -- Z added so nobody lands in the floor
local RV_LIFT = 250        -- GUESS: lands on/beside the RV rather than inside its mesh
local ITEMS_PER_PAGE = 15

---------------------------------------------------------------------------
-- Pure helpers (exported for tests)
---------------------------------------------------------------------------

-- n positions spaced RING_SPACING apart on a circle around `center`, lifted
-- by `lift` (default RING_LIFT). One player stands at the centre.
function M.ring_positions(center, n, spacing, lift)
  spacing = spacing or RING_SPACING
  lift = lift or RING_LIFT
  local out = {}
  local radius = 0
  if n > 1 then radius = spacing / (2 * math.sin(math.pi / n)) end
  for i = 1, n do
    local a = 2 * math.pi * (i - 1) / math.max(n, 1)
    out[i] = {
      X = center.X + radius * math.cos(a),
      Y = center.Y + radius * math.sin(a),
      Z = center.Z + lift,
    }
  end
  return out
end

-- FST_Damage_Results from entries { {tag = <FName or string>, damage = n} }.
-- `fname` converts a string to an FName (identity when unavailable); an
-- FName passed in as `tag` is used as-is.
function M.damage_results(entries, fname)
  fname = fname or function(s) return s end
  local list = {}
  for i, e in ipairs(entries) do
    local tag = e.tag
    if type(tag) == "string" then tag = fname(tag) end
    list[i] = {
      [F_TYPE] = { TagName = tag },
      [F_DAMAGE] = e.damage,
      [F_SHIELD] = 0,
      [F_SKIP] = true,
    }
  end
  return { [F_RESULTS] = list }
end

local function field(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

-- Heal struct from a list of FTagIntPair { Tag.TagName, Value }. Returns nil
-- when there is nothing to heal.
function M.heal_results(pairs_list, fname)
  local entries = {}
  for _, p in ipairs(pairs_list) do
    local tag = field(field(p, "Tag"), "TagName")
    -- An FName read out of an array element may not survive being passed
    -- back; rebuild it from its text when it has one.
    if tag ~= nil and type(tag) ~= "string" then
      local ok, str = pcall(function() return tag:ToString() end)
      if ok and type(str) == "string" and str ~= "" then tag = str end
    end
    local value = field(p, "Value")
    if tag ~= nil and type(value) == "number" then
      entries[#entries + 1] = { tag = tag, damage = value }
    end
  end
  if #entries == 0 then return nil end
  return M.damage_results(entries, fname)
end

local function tostr(v)
  if v == nil then return nil end
  if type(v) == "string" then return v end
  if type(v) == "number" then return tostring(v) end
  local ok, s = pcall(function() return v:ToString() end)
  if ok and type(s) == "string" then return s end
  return nil
end

-- TMap ForEach hands back wrapper params that need :get().
local function unwrap(x)
  if x ~= nil and type(x) ~= "string" and type(x) ~= "number" then
    local ok, v = pcall(function() return x:get() end)
    if ok and v ~= nil then return v end
  end
  return x
end

local function address(obj)
  local ok, a = pcall(function() return obj:GetAddress() end)
  if ok then return a end
  return nil
end

local function same_object(a, b)
  if a == nil or b == nil then return false end
  if rawequal(a, b) then return true end
  local x, y = address(a), address(b)
  return x ~= nil and x == y
end

local function vec(v)
  if v == nil then return nil end
  local ok, t = pcall(function() return { X = v.X, Y = v.Y, Z = v.Z } end)
  if ok and type(t.X) == "number" and type(t.Y) == "number" and type(t.Z) == "number" then
    return t
  end
  return nil
end

local function short(err)
  return tostring(err):sub(1, 80)
end

-- TArray -> Lua list (UE4SS arrays support # and 1-based indexing).
local function to_list(arr)
  local out = {}
  if arr == nil then return out end
  local ok = pcall(function()
    for i = 1, #arr do out[#out + 1] = arr[i] end
  end)
  if not ok then return {} end
  return out
end

---------------------------------------------------------------------------
-- Construction and lookups
---------------------------------------------------------------------------

function M.new(opts)
  return setmetatable({
    ue = opts.ue,
    logger = opts.logger,
    cfg = opts.cfg or {},
    env = opts.env or _G,
    items = opts.items,  -- static item list (lib/items.lua); see static_items
    speed_on = {},      -- name -> bool; speed has no readable state
    god_all = false,
    god_on = {},        -- "me" or player name -> true while god mode is kept on
  }, Actions)
end

local function log(self, level, msg)
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

function Actions:fname(s)
  local fn = lookup(self.env, "FName")
  if callable(fn) then
    local ok, v = pcall(fn, s)
    if ok then return v end
  end
  return s
end

function Actions:valid(obj)
  return obj ~= nil and self.ue:is_valid(obj)
end

-- FindFirstOf matches the exact class name, not subclasses, and the game
-- mode here is a Blueprint subclass of RGGameMode. Try the known names, then
-- ask the local pawn/controller: only the server holds authority over them.
local GAME_MODES = { "GameModeBase", "RGGameMode", "GameMode", "BP_GameMode_C", "BP_RideGameMode_C" }

function Actions:is_host()
  for _, name in ipairs(GAME_MODES) do
    if self:valid(self.ue:find_first(name)) then return self:note_host(true, name) end
  end
  local pc = self:local_controller()
  local pawn = pc and self.ue:get(pc, "Pawn")
  for _, obj in ipairs({ pawn or false, pc or false }) do
    if obj and self:valid(obj) then
      local ok, auth = self.ue:call(obj, "HasAuthority")
      if ok and auth == true then return self:note_host(true, "HasAuthority") end
    end
  end
  local role = pawn and self.ue:get(pawn, "Role")
  local nmode
  local find = lookup(self.env, "StaticFindObject")
  if pawn and callable(find) then
    local okk, ksl = pcall(find, "/Script/Engine.Default__KismetSystemLibrary")
    if okk and ksl ~= nil and self:valid(ksl) then
      local oks, server = self.ue:call_quiet(ksl, "IsServer", pawn)
      if oks and server == true then return self:note_host(true, "IsServer") end
      nmode = tostring(server)
    end
  end
  return self:note_host(false, string.format("no game mode, no authority; pawn Role %s, IsServer %s",
    tostring(role), tostring(nmode)))
end

function Actions:note_host(host, why)
  local line = string.format("host check: %s (%s)", host and "host" or "client", why)
  if line ~= self.last_host_line then
    self.last_host_line = line
    log(self, "info", line)
  end
  return host
end

function Actions:local_controller()
  for _, pc in ipairs(self.ue:find_all("BP_FirstPersonPlayerController_C")) do
    if self:valid(pc) then
      local ok, is_local = self.ue:call(pc, "IsLocalController")
      if ok and is_local == true then return pc end
    end
  end
  local pc = self.ue:find_first("PlayerController")
  if self:valid(pc) then return pc end
  return nil
end

function Actions:local_pawn()
  local pc = self:local_controller()
  if not pc then return nil end
  local pawn = self.ue:get(pc, "Pawn")
  if self:valid(pawn) then return pawn end
  return nil
end

function Actions:cheat_manager()
  local pc = self:local_controller()
  if not pc then return nil end
  local cm = self.ue:get(pc, "CheatManager")
  if self:valid(cm) then return cm end
  return nil
end

-- Runs a cheat-manager function. false, reason on any failure.
function Actions:cheat(fn_name, ...)
  local cm = self:cheat_manager()
  if not cm then return false, "no cheat manager" end
  local res = table.pack(self.ue:call(cm, fn_name, ...))
  if not res[1] then return false, short(res[2]) end
  return true
end

-- Every valid player pawn as { pawn, ref = {name, addr} }. Names come from
-- the player state; a missing one becomes "Player N", and a duplicate gets
-- " (2)" so menu rows stay distinguishable.
function Actions:players()
  local out, seen = {}, {}
  local pawns = self.ue:find_all("BP_FirstPersonCharacter_C")
  local bad_pawn, no_state = 0, 0
  for i, pawn in ipairs(pawns) do
    if not self:valid(pawn) then bad_pawn = bad_pawn + 1 end
    if self:valid(pawn) then
      local name
      local ps = self.ue:get(pawn, "PlayerState")
      -- A pawn with no player state is a leftover body (after death and
      -- revive the player gets a new pawn); listing it made Kill hit the
      -- corpse instead of the player.
      if self:valid(ps) then
        local ok, s = self.ue:call_quiet(ps, "GetPlayerName")
        if ok then name = tostr(s) end
        if name == nil or name == "" then name = tostr(self.ue:get(ps, "PlayerNamePrivate")) end
        if name == nil or name == "" then name = "Player " .. i end
      else
        no_state = no_state + 1
      end
      if name ~= nil then
        seen[name] = (seen[name] or 0) + 1
        if seen[name] > 1 then name = name .. " (" .. seen[name] .. ")" end
        out[#out + 1] = { pawn = pawn, ref = { name = name, addr = address(pawn) } }
      end
    end
  end
  -- One line per change, so an empty Players page can be diagnosed from
  -- the log without spamming it on every redraw.
  local summary = string.format("players: %d pawns, %d listed, %d invalid, %d without player state",
    #pawns, #out, bad_pawn, no_state)
  if summary ~= self.last_players_summary then
    self.last_players_summary = summary
    log(self, "info", summary)
  end
  return out
end

-- Re-finds a player at action time: by address, else by name.
function Actions:resolve(ref)
  if type(ref) ~= "table" then return nil end
  local list = self:players()
  for _, p in ipairs(list) do
    if ref.addr ~= nil and p.ref.addr == ref.addr then return p.pawn, p.ref.name end
  end
  for _, p in ipairs(list) do
    if p.ref.name == ref.name then return p.pawn, p.ref.name end
  end
  return nil
end

function Actions:location(actor)
  local ok, v = self.ue:call(actor, "K2_GetActorLocation")
  if ok then return vec(v) end
  return nil
end

function Actions:rotation(actor)
  local ok, r = self.ue:call(actor, "K2_GetActorRotation")
  if not ok or r == nil then return nil end
  local okr, t = pcall(function() return { Pitch = r.Pitch, Yaw = r.Yaw, Roll = r.Roll } end)
  if okr and type(t.Yaw) == "number" then return t end
  return nil
end

function Actions:vehicle()
  local v = self.ue:find_first("BP_VehicleBase_C")
  if self:valid(v) then return v end
  return nil
end

---------------------------------------------------------------------------
-- Teleport
---------------------------------------------------------------------------

-- Teleports pawn P to location L (a plain {X,Y,Z}). Returns true if either
-- step reported success.
function Actions:teleport(p, loc, rot)
  rot = rot or self:rotation(p) or { Pitch = 0, Yaw = 0, Roll = 0 }
  -- C++ ARGFirstPersonCharacter::TeleportPlayerTo, the game's own teleport.
  local ok1 = self.ue:call(p, "TeleportPlayerTo", loc, rot)
  local ok2 = false
  if not same_object(p, self:local_pawn()) then
    -- Movement is client-authoritative: this Client RPC runs on the target's
    -- own machine. GUESS: that it moves a live (not just revived) player.
    ok2 = self.ue:call(p, "Client_MovePlayerAfterRevive", loc)
  end
  return ok1 == true or ok2 == true
end

-- Teleports each pawn in `pawns` onto a ring around `center` (+ ring lift).
function Actions:teleport_many(pawns, center, label)
  if #pawns == 0 then return "no players to move" end
  local spots = M.ring_positions(center, #pawns)
  local moved = 0
  for i, p in ipairs(pawns) do
    if self:teleport(p, spots[i]) then moved = moved + 1 end
  end
  if moved == 0 then return "teleport failed" end
  return string.format("Teleported %d/%d %s", moved, #pawns, label or "")
end

function Actions:all_pawns()
  local out = {}
  for _, p in ipairs(self:players()) do out[#out + 1] = p.pawn end
  return out
end

function Actions:rv_center()
  local v = self:vehicle()
  if not v then return nil, "no RV found" end
  local loc = self:location(v)
  if not loc then return nil, "can't read RV position" end
  return { X = loc.X, Y = loc.Y, Z = loc.Z + RV_LIFT }
end

function Actions:me_to_rv()
  local ok = self:cheat("TeleportToVehicle")
  if ok then return "Teleported to RV" end
  local center, why = self:rv_center()
  local me = self:local_pawn()
  if not center then return why end
  if not me then return "no local player" end
  return self:teleport_many({ me }, center, "to RV")
end

function Actions:everyone_to_rv()
  local center, why = self:rv_center()
  if not center then return why end
  return self:teleport_many(self:all_pawns(), center, "to RV")
end

function Actions:me_to_checkpoint(n)
  local ok, why = self:cheat("TeleportToCheckpoint", n)
  if ok then return "Teleporting to checkpoint " .. n end
  return "Checkpoint failed: " .. why
end

function Actions:restart_at_checkpoint(n)
  local ok, why = self:cheat("RestartAtCheckpoint", n)
  if ok then return "Restarting at checkpoint " .. n end
  return "Restart failed: " .. why
end

-- Loaded checkpoints as a sorted list of { index, actor }. They stream in,
-- so this can legitimately be empty.
function Actions:checkpoints()
  local by_index = {}
  for _, cp in ipairs(self.ue:find_all("BP_CheckPoint_C")) do
    if self:valid(cp) then
      local idx = self.ue:get(cp, "CheckpointIndex")
      if type(idx) == "number" and by_index[idx] == nil then by_index[idx] = cp end
    end
  end
  local out = {}
  for idx, cp in pairs(by_index) do out[#out + 1] = { index = idx, actor = cp } end
  table.sort(out, function(a, b) return a.index < b.index end)
  return out
end

function Actions:everyone_to_checkpoint(index)
  for _, c in ipairs(self:checkpoints()) do
    if c.index == index then
      local loc = self:location(c.actor)
      if not loc then return "can't read checkpoint position" end
      return self:teleport_many(self:all_pawns(), loc, "to checkpoint " .. index)
    end
  end
  return "checkpoint " .. tostring(index) .. " is no longer loaded"
end

function Actions:bring_everyone()
  local me = self:local_pawn()
  if not me then return "no local player" end
  local loc = self:location(me)
  if not loc then return "can't read your position" end
  local others = {}
  for _, p in ipairs(self:all_pawns()) do
    if not same_object(p, me) then others[#others + 1] = p end
  end
  return self:teleport_many(others, loc, "to you")
end

function Actions:bring_rv()
  local me, v = self:local_pawn(), self:vehicle()
  if not me then return "no local player" end
  if not v then return "no RV found" end
  local loc = self:location(me)
  if not loc then return "can't read your position" end
  local ok, f = self.ue:call(me, "GetActorForwardVector")
  local fv = ok and vec(f) or { X = 0, Y = 0, Z = 0 }
  local dest = { X = loc.X + fv.X * 600, Y = loc.Y + fv.Y * 600, Z = loc.Z + 100 }
  local okf, err = self.ue:call(v, "ForceTeleport", dest)
  if okf then return "RV moved to you" end
  return "RV move failed: " .. short(err)
end

function Actions:player_to_me(p)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local loc = self:location(me)
  if not loc then return "can't read your position" end
  return self:teleport_many({ p }, loc, "to you")
end

function Actions:me_to_player(p)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local loc = self:location(p)
  if not loc then return "can't read their position" end
  return self:teleport_many({ me }, loc, "to them")
end

function Actions:player_to_rv(p)
  local center, why = self:rv_center()
  if not center then return why end
  return self:teleport_many({ p }, center, "to RV")
end

---------------------------------------------------------------------------
-- Health
---------------------------------------------------------------------------

function Actions:revive(p)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local ok = self.ue:call(me, "ServerReviveTarget", p, true, true, me)
  if ok then return "Revive sent" end
  local loc = self:location(p)
  if loc and self.ue:call(me, "Server_RevivePlayerAtLocation", p, loc) then
    return "Revive sent (at location)"
  end
  return "Revive failed"
end

function Actions:heal(p)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local damage = to_list(self.ue:get(p, "CurrentDamage"))
  local results = M.heal_results(damage, function(s) return self:fname(s) end)
  local _, before = self.ue:call_quiet(p, "GetCurrentDamageTaken")
  local desc = {}
  for _, e in ipairs((results or {})[F_RESULTS] or {}) do
    local t = e[F_TYPE].TagName
    local okt, ts = pcall(function() return type(t) == "string" and t or t:ToString() end)
    desc[#desc + 1] = string.format("%s=%s", okt and tostring(ts) or "?", tostring(e[F_DAMAGE]))
  end
  log(self, "info", string.format("heal: %d damage entries [%s], damage taken %s",
    #damage, table.concat(desc, ", "), tostring(before)))
  if not results then return "already at full health" end
  -- Two routes: the character's own heal RPC and the controller's.
  local ok, err = self.ue:call(me, "Server_HealPlayerDamage", p, results)
  local pc = self:local_controller()
  local ok2 = pc ~= nil and self.ue:call(pc, "Server_HealPlayer", p, results)
  if ok or ok2 then return "Healed" end
  return "Heal failed: " .. short(err)
end

function Actions:kill(p)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local threshold = self.ue:get(p, "DeathDamageThreshold")
  if type(threshold) ~= "number" then return "can't read death threshold" end
  local results = M.damage_results(
    { { tag = "Damage.Default", damage = threshold + 1 } },
    function(s) return self:fname(s) end)
  local ok, err = self.ue:call(me, "Server_TakePlayerDamage", p, results, true)
  if ok then return "Killed" end
  return "Kill failed: " .. short(err)
end

---------------------------------------------------------------------------
-- God mode and speed
---------------------------------------------------------------------------

function Actions:is_god(p)
  return self.ue:get(p, "Invulnerable") == true
end

-- The game's Invulnerable flag is a timed buff (ResetInvulnerableTimer turns
-- it off), so god mode is kept here and re-applied every second until it is
-- switched off.
local GOD_REFRESH_MS = 1000

function Actions:god_targets()
  local out = {}
  if self.god_all then return self:all_pawns() end
  for key in pairs(self.god_on) do
    local p
    if key == "me" then p = self:local_pawn() else p = self:resolve({ name = key }) end
    if p then out[#out + 1] = p end
  end
  return out
end

function Actions:god_active()
  return self.god_all or next(self.god_on) ~= nil
end

function Actions:refresh_god()
  for _, p in ipairs(self:god_targets()) do
    self.ue:call_quiet(p, "Server_UpdateInvulnerable", true)
  end
end

function Actions:start_god_keeper()
  if self.god_loop then return end
  local loop = lookup(self.env, "LoopAsync")
  if not callable(loop) then
    log(self, "warn", "LoopAsync unavailable; god mode will wear off")
    return
  end
  local ok, err = pcall(loop, GOD_REFRESH_MS, function()
    if not self:god_active() then
      self.god_loop = false
      return true   -- stops the loop
    end
    self.ue:in_game_thread(function()
      local okr, e = pcall(self.refresh_god, self)
      if not okr then log(self, "warn", "god refresh failed: " .. tostring(e)) end
    end)
    return false
  end)
  if ok then self.god_loop = true else log(self, "warn", "god keeper failed: " .. tostring(err)) end
end

function Actions:toggle_god(p, name)
  local key = name or "?"
  local want = not self.god_on[key]
  local ok, err = self.ue:call(p, "Server_UpdateInvulnerable", want)
  if not ok then return "God mode failed: " .. short(err) end
  self.god_on[key] = want or nil
  if want then self:start_god_keeper() end
  return want and "God mode ON" or "God mode OFF"
end

-- Speed has no readable state, so it is tracked here.
function Actions:toggle_speed(p, name)
  local me = self:local_pawn()
  if not me then return "no local player" end
  local want = not self.speed_on[name]
  -- GUESS: Time 0 means "no expiry" for the last parameter.
  local ok, err = self.ue:call(me, "Server_UpdateSpeedMultiplier", p, want and 2.0 or 1.0, 0)
  if not ok then return "Speed failed: " .. short(err) end
  self.speed_on[name] = want
  return want and "Speed x2 ON" or "Speed normal"
end

function Actions:toggle_god_all()
  local want = not self.god_all
  local n = 0
  for _, p in ipairs(self:all_pawns()) do
    if self.ue:call(p, "Server_UpdateInvulnerable", want) then n = n + 1 end
  end
  if n == 0 then return "God mode failed" end
  self.god_all = want
  if want then self:start_god_keeper() end
  return string.format("God mode %s for %d", want and "ON" or "OFF", n)
end

function Actions:toggle_god_me()
  local me = self:local_pawn()
  if not me then return "no local player" end
  local want = not self.god_on.me
  local used = {}
  if self:is_host() then
    -- GUESS: GodPlayers(bool) may apply to every player, not just the host.
    if self:cheat("GodPlayers", want) then used[#used + 1] = "cheat" end
  end
  if self.ue:call(me, "Server_UpdateInvulnerable", want) then used[#used + 1] = "rpc" end
  if #used == 0 then return "God mode failed" end
  self.god_on.me = want or nil
  if want then self:start_god_keeper() end
  log(self, "info", string.format("god: want %s, used %s, Invulnerable now %s",
    tostring(want), table.concat(used, "+"), tostring(self:is_god(me))))
  return want and "God mode ON" or "God mode OFF"
end

---------------------------------------------------------------------------
-- Grabs and seats
---------------------------------------------------------------------------

-- UE4SS out params are unverified: the value may come back as an extra
-- return or be written into the table passed in its place. Takes the first
-- number found either way.
local function first_number(res, outs)
  for i = 2, res.n or 0 do
    if type(res[i]) == "number" then return res[i] end
  end
  for _, t in ipairs(outs) do
    if type(t) == "table" then
      for _, v in pairs(t) do
        if type(v) == "number" then return v end
        local ok, g = pcall(function() return v:get() end)
        if ok and type(g) == "number" then return g end
      end
    end
  end
  return nil
end

-- The seat's own seat type (each seat has one; 0 was a wrong guess).
function Actions:seat_type(seat)
  local a, b, c = {}, {}, {}
  local res = table.pack(self.ue:call_quiet(seat, "IsRideable", a, b, c))
  if not res[1] then return nil end
  return first_number(res, { b })
end

local SEATABLE = "BP_Seatable_TruckPart_01_C"

-- The actor p sits on. Normally the attach parent; if that is the RV itself
-- rather than a seat, the nearest seatable part within 250 units.
function Actions:seat_of(p)
  local okp, parent = self.ue:call_quiet(p, "GetAttachParentActor")
  if not okp or not self:valid(parent) then return nil end
  if self:seat_type(parent) ~= nil then return parent end
  local here = self:location(p)
  local best, best_d = nil, 250 * 250
  if here then
    for _, s in ipairs(self.ue:find_all(SEATABLE)) do
      local at = self:valid(s) and self:location(s)
      if at then
        local dx, dy, dz = at.X - here.X, at.Y - here.Y, at.Z - here.Z
        local d = dx * dx + dy * dy + dz * dz
        if d < best_d then best, best_d = s, d end
      end
    end
  end
  return best or parent
end

function Actions:unseat(p)
  local seat = self:seat_of(p)
  if not seat then return false, "not seated" end
  local seat_type = self:seat_type(seat)
  log(self, "info", string.format("unseat: seat %s, type %s",
    self.ue:class_of(seat), tostring(seat_type)))
  -- Own pawn with a known seat type: the same stand-up the unmount key
  -- does. Everyone else: the game's forced exit, which runs on their
  -- machine. v0.2.4 also sent a raw detach and a stand-up with a guessed
  -- seat type, and the seat stayed "occupied" for good.
  if seat_type ~= nil and same_object(p, self:local_pawn()) then
    local ok = self.ue:call(p, "SitOnRideableActor", seat, false, seat_type)
    if ok and self.ue:get(p, "IsPassenger") ~= true then return true, "Unseated" end
  end
  local ok, why = self.ue:call(p, "Client_ForceUnseat", seat)
  if not ok then return false, "Unseat failed: " .. short(why) end
  return true, "Unseated"
end

function Actions:force_unseat(p)
  local _, msg = self:unseat(p)
  return msg
end

function Actions:free(p)
  local zero = { X = 0, Y = 0, Z = 0 }
  local freed = 0
  for _, h in ipairs(self:all_pawns()) do
    if not same_object(h, p) then
      local held = self.ue:get(h, "CurrentPickUpActor")
      local held3 = self.ue:get(h, "Current3rdPersonPickUpActor")
      if same_object(held, p) or same_object(held3, p) then
        self.ue:call(h, "Server_DropActor", p, 0.0, false, zero, false, { X = 0, Y = 0, Z = 0, W = 1 }, zero)
        self.ue:call(h, "TryToClearPickedUpActor", p)
        freed = freed + 1
      end
    end
  end
  -- Monster and monkey grabs are seats.
  local seated = self:unseat(p)
  self.ue:call(p, "Server_Ragdoll", false)
  if freed == 0 and not seated then return "Not grabbed (ragdoll reset sent)" end
  return "Freed"
end

---------------------------------------------------------------------------
-- Items
---------------------------------------------------------------------------

-- Sorted { name, class } list from the cheat manager's registered item
-- table, or nil plus a reason.
function Actions:item_list()
  local cm = self:cheat_manager()
  if not cm then return nil, "no item list available" end
  local map = self.ue:get(cm, "RegisteredItemCommands")
  local out, ok = {}, false
  if map ~= nil then
    ok = self.ue:call_quiet(map, "ForEach", function(k, v)
      local name, cls = tostr(unwrap(k)), unwrap(v)
      if name ~= nil and cls ~= nil then out[#out + 1] = { name = name, class = cls } end
    end)
  end
  if not ok or #out == 0 then out = self:static_items() end
  if #out == 0 then return nil, "no item list available" end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- Release builds leave RegisteredItemCommands empty, so fall back to a fixed
-- list of item class paths (lib/items.lua). v0.2.5-0.2.7 walked the whole
-- object array instead, and that crashed the game.
function Actions:static_items()
  local out = {}
  for _, it in ipairs(self.items or {}) do
    out[#out + 1] = { name = it.name, path = it.path, hand = it.hand }
  end
  return out
end

-- The class for a list entry: already known (registry), else found by path,
-- else loaded by path. nil, reason if it cannot be had.
function Actions:item_class(item)
  if item.class ~= nil then return item.class end
  if type(item.path) ~= "string" then return nil, "no class" end
  local find = lookup(self.env, "StaticFindObject")
  if not callable(find) then return nil, "StaticFindObject unavailable" end
  local function found()
    local ok, c = pcall(find, item.path)
    if ok and c ~= nil and self:valid(c) then return c end
    return nil
  end
  local c = found()
  if c then return c end
  -- Not loaded yet: load the Blueprint asset (path minus the "_C" class
  -- suffix), then look again.
  local load = lookup(self.env, "LoadAsset")
  if callable(load) then
    pcall(load, (item.path:gsub("_C$", "")))
    c = found()
    if c then return c end
  end
  return nil, "item not loaded"
end

function Actions:spawn(item)
  if type(item) ~= "table" then return "no item" end
  local cls, why = self:item_class(item)
  if not cls then return "Spawn failed: " .. why end
  -- Fragile items (nitroglycerin) explode when dropped in front of you, so
  -- they go straight into your hands through the controller's cheat RPC.
  if item.hand then
    local pc = self:local_controller()
    if pc and self.ue:call(pc, "Server_CheatSpawnAndAttach", cls) then
      return "Put " .. item.name .. " in your hands"
    end
    log(self, "warn", "spawn: hand spawn unavailable for " .. item.name .. "; dropping it instead")
  end
  if self:cheat("SpawnItemInFrontOfPlayer", cls) then return "Spawned " .. item.name end
  local ok, why2 = self:cheat("GiveItem", cls)
  if ok then return "Gave " .. item.name end
  return "Spawn failed: " .. why2
end

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------

local function each_player(self, fn)
  local n, total = 0, 0
  for _, p in ipairs(self:all_pawns()) do
    total = total + 1
    if fn(p) then n = n + 1 end
  end
  return n, total
end

-- host = true gates the action to the session host (Actions on other
-- players); false actions work on a client too.
local HANDLERS = {
  tp_me_rv = { fn = function(self) return self:me_to_rv() end },
  tp_all_rv = { host = true, fn = function(self) return self:everyone_to_rv() end },
  tp_me_cp = { fn = function(self, t) return self:me_to_checkpoint(t) end },
  tp_all_cp = { host = true, fn = function(self, t) return self:everyone_to_checkpoint(t) end },
  restart_cp = { fn = function(self, t) return self:restart_at_checkpoint(t) end },
  bring_all = { host = true, fn = function(self) return self:bring_everyone() end },
  bring_rv = { host = true, fn = function(self) return self:bring_rv() end },

  me_god = { fn = function(self) return self:toggle_god_me() end },
  me_revive = { fn = function(self)
    local ok, why = self:cheat("RevivePlayer")
    return ok and "Revived" or ("Revive failed: " .. why)
  end },
  me_heal = { fn = function(self)
    local me = self:local_pawn()
    if not me then return "no local player" end
    return self:heal(me)
  end },
  me_unseat = { fn = function(self)
    local me = self:local_pawn()
    if not me then return "no local player" end
    return self:force_unseat(me)
  end },
  me_epipens = { fn = function(self)
    local ok, why = self:cheat("GiveEpiPens", 5)
    return ok and "Gave 5 epipens" or ("Epipens failed: " .. why)
  end },

  spawn = { fn = function(self, t) return self:spawn(t) end },

  all_revive = { host = true, fn = function(self)
    local me = self:local_pawn()
    if not me then return "no local player" end
    local n, total = each_player(self, function(p)
      return self.ue:call(me, "ServerReviveTarget", p, true, true, me)
    end)
    return string.format("Revive sent to %d/%d", n, total)
  end },
  all_heal = { host = true, fn = function(self)
    local n, total = each_player(self, function(p)
      return self:heal(p) == "Healed"
    end)
    return string.format("Healed %d/%d", n, total)
  end },
  all_free = { host = true, fn = function(self)
    local n, total = each_player(self, function(p)
      self:free(p)
      return true
    end)
    return string.format("Freed %d/%d", n, total)
  end },
  all_god = { host = true, fn = function(self) return self:toggle_god_all() end },
}

-- Per-player actions: the target is a ref; it is re-resolved at run time.
local PLAYER_HANDLERS = {
  p_tp_to_me = function(self, p) return self:player_to_me(p) end,
  p_tp_me_to = function(self, p) return self:me_to_player(p) end,
  p_send_rv = function(self, p) return self:player_to_rv(p) end,
  p_revive = function(self, p) return self:revive(p) end,
  p_heal = function(self, p) return self:heal(p) end,
  p_kill = function(self, p) return self:kill(p) end,
  p_free = function(self, p) return self:free(p) end,
  p_unseat = function(self, p) return self:force_unseat(p) end,
  p_god = function(self, p, name) return self:toggle_god(p, name) end,
  p_speed = function(self, p, name) return self:toggle_speed(p, name) end,
}
for id, fn in pairs(PLAYER_HANDLERS) do
  HANDLERS[id] = {
    host = true,
    fn = function(self, ref)
      local p, name = self:resolve(ref)
      if not p then return "player no longer in session" end
      return fn(self, p, name)
    end,
  }
end

-- Runs an action by id and returns the message to show. Never throws.
function Actions:run(id, target)
  local h = HANDLERS[id]
  if not h then return "Unknown action" end
  if h.host and not self:is_host() then return "Host only" end
  local ok, msg = pcall(h.fn, self, target)
  if not ok then
    log(self, "error", string.format("action %s failed: %s", tostring(id), tostring(msg)))
    return "Error: " .. short(msg)
  end
  log(self, "info", string.format("action %s: %s", tostring(id), tostring(msg)))
  return msg
end

-- Toggle readouts for the menu (read at draw time).
function Actions:player_god(ref)
  return ref ~= nil and self.god_on[ref.name] == true
end

function Actions:player_speed(ref)
  return ref ~= nil and self.speed_on[ref.name] == true
end

function Actions:me_god()
  return self.god_on.me == true
end

M.ITEMS_PER_PAGE = ITEMS_PER_PAGE
Actions.ITEMS_PER_PAGE = ITEMS_PER_PAGE
return M
