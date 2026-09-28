-- dump-game-objects.lua
--
-- TEMPORARY RECON TOOL — this is NOT part of the shipped RVAdminMenu package.
-- It exists only to gather the data for docs/game-objects.md (Task 2 of the
-- admin-menu plan) and should never be distributed alongside the mod.
--
-- Install (as its own throwaway UE4SS mod, separate from RVAdminMenu):
--   <UE4SS mods dir>/RVRecon/scripts/main.lua   <- this file, renamed
--   <UE4SS mods dir>/RVRecon/enabled.txt        <- empty file is fine, just needs to exist
--
-- Usage:
--   1. Launch the game with UE4SS + this mod installed and enabled.
--   2. Host a session with a second player connected (recon needs a live
--      2-player game to answer the questions in docs/game-objects.md).
--   3. Press F9. This logs the object dumps below and also calls
--      DumpAllObjects() for a full UObject listing.
--   4. Collect two files afterwards:
--        - UE4SS.log              (next to UE4SS.dll / the game exe)
--        - ObjectDump.txt         (also written next to UE4SS.dll)
--      Hand both to whoever is filling in docs/game-objects.md.
--
-- Hardening: every UE4SS global this script touches is looked up with
-- rawget(_G, name) and type-checked before use, and every engine call is
-- pcall-guarded. If a global is missing, this prints a "[recon] missing:"
-- line naming it and skips just that section — it must never crash the
-- game it's running inside.

local function get_global(name)
  local v = rawget(_G, name)
  if v == nil then
    print(string.format("[recon] missing: %s (skipping section)\n", name))
    return nil
  end
  return v
end

local function dump(label, className)
  local find_all = get_global("FindAllOf")
  if type(find_all) ~= "function" then return end

  local ok, list = pcall(find_all, className)
  if not ok or type(list) ~= "table" then
    print(string.format("[recon] %s (%s): none\n", label, className))
    return
  end
  for _, o in ipairs(list) do
    local okn, n = pcall(function() return o:GetFullName() end)
    print(string.format("[recon] %s: %s\n", label, okn and n or "<unnamed>"))
  end
end

local function run_dump()
  dump("controller", "PlayerController")
  dump("playerstate", "PlayerState")
  dump("pawn",        "Pawn")
  dump("character",   "Character")
  dump("gamemode",    "GameModeBase")
  dump("gamestate",   "GameStateBase")
  dump("gamesession", "GameSession")
  dump("hud",         "HUD")

  local dump_all = get_global("DumpAllObjects")
  if type(dump_all) == "function" then
    local ok, err = pcall(dump_all)
    if not ok then
      print(string.format("[recon] DumpAllObjects() failed: %s\n", tostring(err)))
    else
      print("[recon] DumpAllObjects() wrote ObjectDump.txt next to UE4SS.dll\n")
    end
  end
end

local register_key = get_global("RegisterKeyBind")
local Key = get_global("Key")
local exec_game_thread = get_global("ExecuteInGameThread")

if type(register_key) == "function" and type(Key) == "table" and Key.F9 ~= nil then
  local ok, err = pcall(register_key, Key.F9, function()
    local function fire()
      local ok2, err2 = pcall(run_dump)
      if not ok2 then
        print(string.format("[recon] dump run failed: %s\n", tostring(err2)))
      end
    end

    if type(exec_game_thread) == "function" then
      local ok3, err3 = pcall(exec_game_thread, fire)
      if not ok3 then
        print(string.format("[recon] ExecuteInGameThread failed: %s\n", tostring(err3)))
      end
    else
      -- No ExecuteInGameThread available; run inline rather than skip the
      -- dump entirely.
      fire()
    end
  end)
  if not ok then
    print(string.format("[recon] RegisterKeyBind(F9) failed: %s\n", tostring(err)))
  else
    print("[recon] F9 bound: press it in-game to dump objects\n")
  end
else
  print("[recon] missing: RegisterKeyBind and/or Key.F9 (F9 dump is unavailable)\n")
end

-- Question 8's ReceiveDrawHUD hook: whether this ever fires decides the
-- entire menu rendering approach (Task 8), so it's the single most
-- important thing this script checks. Print only the first few fires and
-- then go silent, since this hook runs every frame and an unthrottled
-- print here would flood UE4SS.log into uselessness.
do
  local register_hook = get_global("RegisterHook")
  if type(register_hook) == "function" then
    local fires_logged = 0
    local MAX_FIRES_TO_LOG = 5

    local ok, err = pcall(register_hook, "/Script/Engine.HUD:ReceiveDrawHUD", function(hud, w, h)
      if fires_logged >= MAX_FIRES_TO_LOG then return end
      fires_logged = fires_logged + 1

      local okw, wv = pcall(function() return w:get() end)
      local okh, hv = pcall(function() return h:get() end)
      print(string.format(
        "[recon] ReceiveDrawHUD fired (%d/%d shown): %sx%s\n",
        fires_logged, MAX_FIRES_TO_LOG,
        okw and tostring(wv) or "<err>",
        okh and tostring(hv) or "<err>"
      ))

      if fires_logged == MAX_FIRES_TO_LOG then
        print("[recon] ReceiveDrawHUD: further fires will not be logged (throttled)\n")
      end
    end)
    if not ok then
      print(string.format("[recon] RegisterHook(ReceiveDrawHUD) failed: %s\n", tostring(err)))
    else
      print("[recon] ReceiveDrawHUD hook registered\n")
    end
  end
end
