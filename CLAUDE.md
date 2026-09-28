## Project Context

A hotkey-summonable admin/cheat menu mod for the Unity co-op game RV There Yet. The host opens an in-game overlay to spawn items, revive/kill/heal/teleport any player in the session, and warp to specific checkpoints. Built as a plugin for whichever mod loader the RV There Yet community has standardized on, confirmed by surveying existing mods before any code is written.

## Goals

- Hotkey-summonable in-game admin/cheat menu overlay
- Spawn arbitrary items
- Revive, kill, and heal players
- Teleport players
- Warp to specific checkpoints
- Survey existing RV There Yet mods first to match community loader and setup conventions
- Work in co-op sessions with the host acting authoritatively on other players

## Out of scope

- Client-side actions by non-host players
- Anti-cheat evasion or use in unwilling/public lobbies
- Custom art or full uGUI design polish for v1

## Suggested stack

- **C# / .NET (Unity modding)** — RV There Yet is a Unity game; mods are C# assemblies patched into the runtime
- **BepInEx (pending survey)** — Most common Unity loader with Harmony patching; confirm against what existing RV There Yet mods actually use before committing
- **HarmonyX** — Runtime patching of game methods for player state, spawning, and checkpoint logic
- **IMGUI overlay** — Fastest path to a functional debug-style admin menu without asset bundles
