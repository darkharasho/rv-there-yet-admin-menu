package.path = "mod/scripts/?.lua;" .. package.path
local actions_mod = require("lib.actions")
local fake_ue = require("tests.support.fake_ue")

-- A pawn that records every engine call made on it.
local function pawn(name, x, addr)
  local p = { calls = {}, addr = addr, X = x }
  p.PlayerState = { GetPlayerName = function() return { ToString = function() return name end } end }
  p.Invulnerable = false
  p.DeathDamageThreshold = 100
  p.CurrentDamage = {}
  local function rec(fn)
    p[fn] = function(self, ...) self.calls[#self.calls + 1] = { fn = fn, args = { ... } }; return true end
  end
  for _, fn in ipairs({ "TeleportPlayerTo", "Client_MovePlayerAfterRevive", "ServerReviveTarget",
    "Server_RevivePlayerAtLocation", "Server_HealPlayerDamage", "Server_TakePlayerDamage",
    "Server_UpdateInvulnerable", "Server_UpdateSpeedMultiplier", "Server_DropActor",
    "TryToClearPickedUpActor", "Server_Ragdoll", "Client_ForceUnseat",
    "Server_SitOnRideableActor", "K2_DetachFromActor", "SitOnRideableActor" }) do rec(fn) end
  p.GetAddress = function(self) return self.addr end
  p.K2_GetActorLocation = function(self) return { X = self.X, Y = 0, Z = 10 } end
  p.K2_GetActorRotation = function() return { Pitch = 0, Yaw = 90, Roll = 0 } end
  p.GetActorForwardVector = function() return { X = 1, Y = 0, Z = 0 } end
  p.GetAttachParentActor = function() return nil end
  return p
end

local function calls_of(p, fn)
  local out = {}
  for _, c in ipairs(p.calls) do if c.fn == fn then out[#out + 1] = c end end
  return out
end

local function world(opts)
  opts = opts or {}
  local ue = fake_ue.new()
  local host, ann = pawn("Host", 0, 1), pawn("Ann", 1000, 2)
  local cheat = { calls = {} }
  for _, fn in ipairs({ "TeleportToVehicle", "TeleportToCheckpoint", "RestartAtCheckpoint",
    "GodPlayers", "GiveEpiPens", "SpawnItemInFrontOfPlayer", "GiveItem", "RevivePlayer" }) do
    cheat[fn] = function(self, ...) self.calls[#self.calls + 1] = { fn = fn, args = { ... } }; return true end
  end
  local pc = { Pawn = host, CheatManager = cheat, IsLocalController = function() return true end }
  local rv = { calls = {}, K2_GetActorLocation = function() return { X = 500, Y = 500, Z = 0 } end,
    ForceTeleport = function(self, loc) self.calls[#self.calls + 1] = loc end }
  ue.objects.BP_FirstPersonPlayerController_C = { pc }
  ue.objects.BP_FirstPersonCharacter_C = { host, ann }
  ue.objects.BP_VehicleBase_C = { rv }
  if opts.host ~= false then ue.objects.GameModeBase = { {} } end
  local a = actions_mod.new({ ue = ue, cfg = {}, env = {} })
  return a, { ue = ue, host = host, ann = ann, cheat = cheat, rv = rv, pc = pc }
end

describe("ring_positions", function()
  it("puts one player at the centre, lifted", function()
    local r = actions_mod.ring_positions({ X = 10, Y = 20, Z = 30 }, 1)
    assert.same({ X = 10, Y = 20, Z = 80 }, r[1])
  end)

  it("spaces neighbours ~120 units apart", function()
    for _, n in ipairs({ 2, 3, 4, 8 }) do
      local r = actions_mod.ring_positions({ X = 0, Y = 0, Z = 0 }, n)
      local d = math.sqrt((r[1].X - r[2].X) ^ 2 + (r[1].Y - r[2].Y) ^ 2)
      assert.is_true(math.abs(d - 120) < 0.001, "n=" .. n)
      assert.equal(50, r[n].Z)
    end
  end)
end)

describe("damage structs", function()
  it("builds the heal struct from FTagIntPair entries", function()
    local pairs_list = {
      { Tag = { TagName = "Damage.Fall" }, Value = 30 },
      { Tag = { TagName = "Damage.Cold" }, Value = 5 },
    }
    local made = {}
    local r = actions_mod.heal_results(pairs_list, function(s) made[#made + 1] = s; return "FN:" .. s end)
    local list = r["DamageResults_3_42A87BC046D21D82BBBC0E856286E2CD"]
    assert.equal(2, #list)
    local e = list[1]
    assert.equal("FN:Damage.Fall", e["DamageType_3_42A87BC046D21D82BBBC0E856286E2CD"].TagName)
    assert.equal(30, e["Damage_7_F3292EDF44790F4AED9654BACA71838A"])
    assert.equal(0, e["MaxVehicleShieldConsumption_10_E95C0831458EF361CE55AF89624199AE"])
    assert.is_true(e["SkipVehicleShield_12_17FC8070442367387C3CBFB05060541B"])
  end)

  it("returns nil when there is nothing to heal", function()
    assert.is_nil(actions_mod.heal_results({}))
  end)

  it("passes non-string tag names through unchanged", function()
    local fname = { opaque = true }
    local r = actions_mod.heal_results({ { Tag = { TagName = fname }, Value = 1 } },
      function() error("must not convert") end)
    assert.equal(fname, r["DamageResults_3_42A87BC046D21D82BBBC0E856286E2CD"][1]
      ["DamageType_3_42A87BC046D21D82BBBC0E856286E2CD"].TagName)
  end)
end)

describe("host gating", function()
  it("blocks actions on other players on a client", function()
    local a, w = world({ host = false })
    assert.equal("Host only", a:run("tp_all_rv"))
    assert.equal("Host only", a:run("p_kill", { name = "Ann", addr = 2 }))
    assert.equal("Host only", a:run("all_heal"))
    assert.equal("Host only", a:run("me_heal"))
    assert.equal("Host only", a:run("me_scrap", 10))
    assert.equal(0, #w.ann.calls)
  end)

  it("turns host god mode on through the cheat and the pawn RPC", function()
    local a, w = world()
    assert.equal("God mode ON", a:run("me_god"))
    assert.equal("GodPlayers", w.cheat.calls[1].fn)
    assert.same({ true }, w.cheat.calls[1].args)
    assert.equal(1, #calls_of(w.host, "Server_UpdateInvulnerable"))
    assert.is_true(a:me_god())
  end)

  it("keeps god mode on by re-applying it until switched off", function()
    local a, w = world()
    local tick
    a.env = { LoopAsync = function(_, fn) tick = fn end }
    w.ue.in_game_thread = function(_, fn) fn() end
    a:run("me_god")
    assert.is_false(tick())
    assert.is_false(tick())
    local rpc = calls_of(w.host, "Server_UpdateInvulnerable")
    assert.equal(3, #rpc)
    assert.same({ true }, rpc[3].args)
    a:run("me_god")
    assert.is_true(tick())   -- off: the loop stops
    assert.is_false(a:me_god())
  end)

  it("finds the host through a game-mode subclass name", function()
    local a, w = world({ host = false })
    w.ue.objects.RGGameMode = { {} }
    assert.is_true(a:is_host())
  end)

  it("finds the host through the local pawn's authority", function()
    local a, w = world({ host = false })
    w.host.HasAuthority = function() return true end
    assert.is_true(a:is_host())
  end)

  it("stays a client when the pawn lacks authority", function()
    local a, w = world({ host = false })
    w.host.HasAuthority = function() return false end
    assert.is_false(a:is_host())
  end)

  it("lets self actions run on a client", function()
    local a, w = world({ host = false })
    assert.equal("Teleported to RV", a:run("tp_me_rv"))
    assert.equal("TeleportToVehicle", w.cheat.calls[1].fn)
    assert.equal("Teleporting to checkpoint 4", a:run("tp_me_cp", 4))
    assert.same({ 4 }, w.cheat.calls[2].args)
    -- God mode on a client skips the cheat and uses the pawn RPC.
    a:run("me_god")
    assert.equal(0, #w.cheat.calls - 2)
    assert.equal(1, #calls_of(w.host, "Server_UpdateInvulnerable"))
  end)

  it("reports an unknown action instead of throwing", function()
    local a = world()
    assert.equal("Unknown action", a:run("nope"))
  end)
end)

describe("player resolution", function()
  it("says the player left when the target is gone", function()
    local a = world()
    assert.equal("player no longer in session", a:run("p_revive", { name = "Zed", addr = 99 }))
  end)

  it("numbers duplicate and missing names", function()
    local a, w = world()
    w.ann.PlayerState = nil
    w.host.PlayerState = { GetPlayerName = function() return "Ann" end }
    w.ann.PlayerState = { GetPlayerName = function() return "Ann" end }
    local names = {}
    for _, p in ipairs(a:players()) do names[#names + 1] = p.ref.name end
    assert.same({ "Ann", "Ann (2)" }, names)
  end)
end)

describe("teleport", function()
  it("moves a remote player with both the C++ teleport and the client RPC", function()
    local a, w = world()
    a:run("p_tp_to_me", { name = "Ann", addr = 2 })
    local tp = calls_of(w.ann, "TeleportPlayerTo")
    assert.equal(1, #tp)
    assert.same({ X = 0, Y = 0, Z = 60 }, tp[1].args[1])
    assert.equal(1, #calls_of(w.ann, "Client_MovePlayerAfterRevive"))
  end)

  it("moves the local pawn without the client RPC", function()
    local a, w = world()
    a:run("p_tp_me_to", { name = "Ann", addr = 2 })
    assert.equal(1, #calls_of(w.host, "TeleportPlayerTo"))
    assert.equal(0, #calls_of(w.host, "Client_MovePlayerAfterRevive"))
    assert.equal(1000, calls_of(w.host, "TeleportPlayerTo")[1].args[1].X)
  end)

  it("sends everyone to the RV on a ring above it", function()
    local a, w = world()
    assert.equal("Teleported 2/2 to RV", a:run("tp_all_rv"))
    local l1 = calls_of(w.host, "TeleportPlayerTo")[1].args[1]
    local l2 = calls_of(w.ann, "TeleportPlayerTo")[1].args[1]
    assert.equal(300, l1.Z)
    assert.is_true(math.abs(math.sqrt((l1.X - l2.X) ^ 2 + (l1.Y - l2.Y) ^ 2) - 120) < 0.001)
  end)

  it("falls back to a manual teleport when the cheat is unavailable", function()
    local a, w = world()
    w.ue.fail_on["call:TeleportToVehicle"] = true
    a:run("tp_me_rv")
    assert.equal(1, #calls_of(w.host, "TeleportPlayerTo"))
  end)

  it("brings everyone else to me and the RV to me", function()
    local a, w = world()
    a:run("bring_all")
    assert.equal(0, #calls_of(w.host, "TeleportPlayerTo"))
    assert.equal(1, #calls_of(w.ann, "TeleportPlayerTo"))
    a:run("bring_rv")
    assert.same({ X = 600, Y = 0, Z = 110 }, w.rv.calls[1])
  end)

  it("sends everyone to a loaded checkpoint by index", function()
    local a, w = world()
    w.ue.objects.BP_CheckPoint_C = {
      { CheckpointIndex = 3, K2_GetActorLocation = function() return { X = 7, Y = 8, Z = 9 } end },
      { CheckpointIndex = 1, K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end },
    }
    local cps = a:checkpoints()
    assert.equal(1, cps[1].index)
    assert.equal(3, cps[2].index)
    a:run("tp_all_cp", 3)
    assert.equal(1, #calls_of(w.ann, "TeleportPlayerTo"))
    assert.equal("checkpoint 9 is no longer loaded", a:run("tp_all_cp", 9))
  end)
end)

describe("health actions", function()
  it("heals with a struct built from CurrentDamage", function()
    local a, w = world()
    w.ann.CurrentDamage = { { Tag = { TagName = "Damage.Fall" }, Value = 12 } }
    assert.equal("Healed", a:run("p_heal", { name = "Ann", addr = 2 }))
    local c = calls_of(w.host, "Server_HealPlayerDamage")[1]
    assert.equal(w.ann, c.args[1])
    assert.equal(12, c.args[2]["DamageResults_3_42A87BC046D21D82BBBC0E856286E2CD"][1]
      ["Damage_7_F3292EDF44790F4AED9654BACA71838A"])
  end)

  it("says 'already at full health' for an empty CurrentDamage", function()
    local a = world()
    assert.equal("already at full health", a:run("p_heal", { name = "Ann", addr = 2 }))
  end)

  it("kills with threshold+1 Damage.Default and Killbox", function()
    local a, w = world()
    a:run("p_kill", { name = "Ann", addr = 2 })
    local c = calls_of(w.host, "Server_TakePlayerDamage")[1]
    local e = c.args[2]["DamageResults_3_42A87BC046D21D82BBBC0E856286E2CD"][1]
    assert.equal(101, e["Damage_7_F3292EDF44790F4AED9654BACA71838A"])
    assert.equal("Damage.Default", e["DamageType_3_42A87BC046D21D82BBBC0E856286E2CD"].TagName)
    assert.is_true(c.args[3])
  end)

  it("revives via the local pawn, falling back to location revive", function()
    local a, w = world()
    a:run("p_revive", { name = "Ann", addr = 2 })
    assert.equal(1, #calls_of(w.host, "ServerReviveTarget"))
    w.ue.fail_on["call:ServerReviveTarget"] = true
    a:run("p_revive", { name = "Ann", addr = 2 })
    assert.equal(1, #calls_of(w.host, "Server_RevivePlayerAtLocation"))
  end)

  it("toggles god mode and tracks speed", function()
    local a, w = world()
    local ref = { name = "Ann", addr = 2 }
    assert.equal("God mode ON", a:run("p_god", ref))
    assert.is_true(calls_of(w.ann, "Server_UpdateInvulnerable")[1].args[1])
    a:run("p_speed", ref)
    assert.equal(2.0, calls_of(w.host, "Server_UpdateSpeedMultiplier")[1].args[2])
    assert.is_true(a:player_speed(ref))
    a:run("p_speed", ref)
    assert.equal(1.0, calls_of(w.host, "Server_UpdateSpeedMultiplier")[2].args[2])
  end)
end)

describe("free and unseat", function()
  it("drops a victim held by another player", function()
    local a, w = world()
    w.host.CurrentPickUpActor = w.ann
    a:run("p_free", { name = "Ann", addr = 2 })
    assert.equal(1, #calls_of(w.host, "Server_DropActor"))
    assert.equal(1, #calls_of(w.host, "TryToClearPickedUpActor"))
    assert.equal(1, #calls_of(w.ann, "Server_Ragdoll"))
  end)

  it("unseats a seated player and reports not seated otherwise", function()
    local a, w = world()
    assert.equal("not seated", a:run("p_unseat", { name = "Ann", addr = 2 }))
    local seat = {}
    w.ann.GetAttachParentActor = function() return seat end
    assert.equal("Unseated", a:run("p_unseat", { name = "Ann", addr = 2 }))
    assert.equal(1, #calls_of(w.ann, "Client_ForceUnseat"))
    assert.equal(0, #calls_of(w.ann, "K2_DetachFromActor"))       -- raw detach broke the seat
    assert.equal(0, #calls_of(w.ann, "Server_SitOnRideableActor"))
  end)

  -- A car seat: reports its seat type through IsRideable's out param.
  local function car_seat(seat_type, x)
    return {
      IsRideable = function(_, _, out_type) out_type.SeatType = seat_type end,
      K2_GetActorLocation = function() return { X = x or 0, Y = 0, Z = 10 } end,
    }
  end

  it("stands the host up from a car seat with that seat's type", function()
    local a, w = world()
    local seat = car_seat(3)
    w.host.GetAttachParentActor = function() return seat end
    assert.equal("Unseated", a:run("me_unseat"))
    local sit = calls_of(w.host, "SitOnRideableActor")
    assert.equal(1, #sit)
    assert.equal(seat, sit[1].args[1])
    assert.is_false(sit[1].args[2])
    assert.equal(3, sit[1].args[3])
    assert.equal(0, #calls_of(w.host, "Client_ForceUnseat"))
  end)

  it("force-unseats another player from their seat", function()
    local a, w = world()
    local seat = car_seat(5)
    w.ann.GetAttachParentActor = function() return seat end
    assert.equal("Unseated", a:run("p_unseat", { name = "Ann", addr = 2 }))
    assert.equal(seat, calls_of(w.ann, "Client_ForceUnseat")[1].args[1])
    assert.equal(0, #calls_of(w.ann, "SitOnRideableActor"))
  end)

  it("finds the nearest seat when attached to the RV itself", function()
    local a, w = world()
    local near, far = car_seat(2, 1050), car_seat(4, 5000)
    w.ue.objects.BP_Seatable_TruckPart_01_C = { far, near }
    w.ann.GetAttachParentActor = function() return w.rv end
    a:run("p_unseat", { name = "Ann", addr = 2 })
    assert.equal(near, calls_of(w.ann, "Client_ForceUnseat")[1].args[1])
  end)
end)

describe("players", function()
  it("skips leftover bodies with no player state", function()
    local a, w = world()
    local corpse = pawn("x", 50, 3)
    corpse.PlayerState = nil
    w.ue.objects.BP_FirstPersonCharacter_C = { w.host, corpse, w.ann }
    local names = {}
    for _, p in ipairs(a:players()) do names[#names + 1] = p.ref.name end
    assert.same({ "Host", "Ann" }, names)
  end)
end)

describe("items", function()
  it("gives scrap through the cheat, falling back to the parts RPC", function()
    local a, w = world()
    w.cheat.GivePart = function(self, n) self.calls[#self.calls + 1] = { fn = "GivePart", args = { n } }; return true end
    assert.equal("Gave 50 scrap", a:run("me_scrap", 50))
    assert.same({ 50 }, w.cheat.calls[1].args)
    w.ue.fail_on["call:GivePart"] = true
    w.host.Server_UpdatePartsCount = function(self, n) self.parts = n end
    assert.equal("Gave 10 scrap", a:run("me_scrap", 10))
    assert.equal(10, w.host.parts)
  end)

  it("spawns fragile items straight into the hands", function()
    local a, w = world()
    w.pc.Server_CheatSpawnAndAttach = function(self, cls) self.attached = cls; return true end
    assert.equal("Put Nitro in your hands", a:run("spawn", { name = "Nitro", class = "N", hand = true }))
    assert.equal("N", w.pc.attached)
    assert.equal(0, #w.cheat.calls)
  end)

  it("never walks the cheat manager's item registry", function()
    local a, w = world()
    local walked = false
    w.cheat.RegisteredItemCommands = { ForEach = function() walked = true end }
    a.items = { { name = "Axe", path = "/Game/A.A_C" } }
    local list = a:item_list()
    assert.is_false(walked)
    assert.equal("Axe", list[1].name)
  end)

  it("falls back to GiveItem, and reports an empty list", function()
    local a, w = world()
    w.ue.fail_on["call:SpawnItemInFrontOfPlayer"] = true
    a:run("spawn", { name = "x", class = "C" })
    assert.equal("GiveItem", w.cheat.calls[1].fn)
    local list, why = a:item_list()
    assert.is_nil(list)
    assert.equal("no item list available", why)
  end)

  it("falls back to the static item list and resolves classes by path", function()
    local a, w = world()
    local cls = {}
    local loaded = {}
    a.items = { { name = "Wrench", path = "/Game/W.W_C" }, { name = "Axe", path = "/Game/A.A_C" } }
    a.env = {
      StaticFindObject = function(path) return loaded[path] end,
      LoadAsset = function(path) if path == "/Game/A.A" then loaded["/Game/A.A_C"] = cls end end,
    }
    local list = a:item_list()
    assert.equal("Axe", list[1].name)
    assert.equal("Spawned Axe", a:run("spawn", list[1]))
    assert.equal(cls, w.cheat.calls[1].args[1])
    assert.equal("Spawn failed: item not loaded", a:run("spawn", list[2]))
  end)

  it("keeps the hand flag from the static list", function()
    local a, w = world()
    local cls = {}
    a.items = { { name = "Nitro", path = "/Game/N.N_C", hand = true } }
    a.env = { StaticFindObject = function() return cls end }
    w.pc.Server_CheatSpawnAndAttach = function(self, c) self.attached = c; return true end
    assert.equal("Put Nitro in your hands", a:run("spawn", a:item_list()[1]))
    assert.equal(cls, w.pc.attached)
  end)
end)
