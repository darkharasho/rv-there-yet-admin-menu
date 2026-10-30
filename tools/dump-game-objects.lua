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

-- Question 10: the exact spellings in UE4SS's Key table. config.lua
-- advertises INSERT/HOME/END/DELETE/PAGE_UP/PAGE_DOWN as valid Hotkey
-- values on nothing but a guess, and ue.lua refuses to bind a name this
-- table does not contain. Printed sorted so the answer can be pasted
-- verbatim into docs/game-objects.md.
local function dump_key_names()
  local keys = rawget(_G, "Key")
  if type(keys) ~= "table" then
    print("[recon] missing: Key table (question 10 unanswerable)\n")
    return
  end
  local names = {}
  local ok = pcall(function()
    for name in pairs(keys) do names[#names + 1] = tostring(name) end
  end)
  if not ok then
    print("[recon] Key: could not iterate the table\n")
    return
  end
  table.sort(names)
  print(string.format("[recon] Key: %d names\n", #names))
  for _, name in ipairs(names) do
    print(string.format("[recon] Key name: %s\n", name))
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
  dump("rv character",   "BP_FirstPersonCharacter_C")
  dump("rv controller",  "BP_FirstPersonPlayerController_C")
  dump("rv playerstate", "BP_PlayerState_C")
  dump("rv checkpoint",  "BP_CheckPoint_C")
  dump("rv cheatmanager", "RGCheatManager")
  dump_key_names()

  -- GenerateSDK writes CXXHeaderDump/ (every loaded class, including the
  -- Blueprint functions' parameter lists); DumpUSMAP writes Mappings.usmap,
  -- which lets the paks be read offline with their property data.
  for _, name in ipairs({ "GenerateSDK", "DumpUSMAP" }) do
    local fn = get_global(name)
    if type(fn) == "function" then
      local ok, err = pcall(fn)
      print(string.format("[recon] %s() %s\n", name, ok and "done" or ("failed: " .. tostring(err))))
    end
  end

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
      -- FindAllOf, GetFullName(), and DumpAllObjects() are unsafe to call
      -- off the game thread. Without ExecuteInGameThread there is no safe
      -- way to run the dump, so skip it rather than risk crashing the
      -- game — a recon tool that crashes the session is worse than one
      -- that logs why it did nothing.
      print("[recon] missing: ExecuteInGameThread (skipping dump — unsafe to run engine calls off the game thread)\n")
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
    local draw_fns_checked = false

    local ok, err = pcall(register_hook, "/Script/Engine.HUD:ReceiveDrawHUD", function(hud, w, h)
      -- One-shot probe of DrawRect/DrawText callability, on the first
      -- fire only, so it never repeats alongside the throttled fires.
      if not draw_fns_checked then
        draw_fns_checked = true
        local okp, err_probe = pcall(function()
          print(string.format("[recon] ReceiveDrawHUD: type(hud.DrawRect) = %s\n", type(hud.DrawRect)))
          print(string.format("[recon] ReceiveDrawHUD: type(hud.DrawText) = %s\n", type(hud.DrawText)))
        end)
        if not okp then
          print(string.format("[recon] ReceiveDrawHUD: DrawRect/DrawText probe failed: %s\n", tostring(err_probe)))
        end
      end

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
