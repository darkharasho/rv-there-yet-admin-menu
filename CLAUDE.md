## Project Context

A hotkey-summonable admin/cheat menu mod for the Unreal Engine 5.6 co-op game RV There Yet. The host opens an in-game overlay to spawn items, revive/kill/heal/teleport any player in the session, and warp to specific checkpoints. Built as a UE4SS Lua mod loaded through unreal_shimloader and installed via HML.

## Goals

- Hotkey-summonable in-game admin/cheat menu overlay
- Spawn arbitrary items
- Revive, kill, and heal players
- Teleport players
- Warp to specific checkpoints
- Work in co-op sessions with the host acting authoritatively on other players

## Out of scope

- Client-side actions by non-host players
- Anti-cheat evasion or use in unwilling/public lobbies
- Custom art or full uGUI design polish for v1

## Stack

- **Lua (UE4SS)** under `mod/scripts/`, run by RE-UE4SS through `Thunderstore-unreal_shimloader`; installed with HML. Engine names are in `docs/game-objects.md` and the CXXHeaderDump.
- **UMG built from Lua** for the overlay (the HUD draw hook never fires); keyboard-driven.
- **busted** tests: `nice -n 19 taskset -c 0-3 scripts/test.sh`. Engine access goes through `lib/ue.lua`, faked in `tests/support/fake_ue.lua`.
- Package: `scripts/build-package.sh` zips the contents of `mod/` plus manifest, icon, README at the zip root.
