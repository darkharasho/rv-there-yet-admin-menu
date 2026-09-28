# Spec: RV There Yet Admin Menu

## Product

A hotkey-summonable admin/cheat overlay for *RV There Yet?* (Nuggets Entertainment, 2025).
The **host** of a co-op session opens an in-game menu and can:

- Spawn arbitrary items
- Revive / kill / heal any player in the session
- Teleport players (to host, to another player, to a marked point)
- Warp to specific checkpoints

The menu is **mouse-driven**: rows are hover-highlighted and clicked with the left mouse
button, with keyboard navigation kept as an equal-footing fallback. This is a product
requirement, not a nice-to-have, and it constrains the rendering approach (below).

### Rendering approach — decided 2026-09-27

UE4SS exposes **ImGui to C++ mods only**; its Lua API has no GUI bindings. Mouse support
therefore forces a choice between three real options:

| Option | Mouse | Toolchain cost |
|---|---|---|
| Lua + `AHUD` canvas drawing + hand-rolled hit-testing | yes | none |
| Blueprint/pak UMG widget + Lua logic | yes, native | Unreal Editor 5.x (~100 GB), version-matched |
| C++ UE4SS mod with real ImGui | yes, native | Windows + MSVC; not cross-compilable from this Linux dev box |

**Chosen: the Lua + `AHUD` canvas path.** The menu is drawn as rectangles and text from a
hook on the HUD's draw event; the mod reads the mouse position and left-button state from
the local `PlayerController` and does point-in-rect hit-testing itself. This keeps the mod
pure Lua, matches the community convention, needs no build toolchain, and — because layout
and hit-testing are ordinary arithmetic — makes the mouse behaviour unit-testable headless.

This choice depends on the game actually having an `AHUD` subclass whose draw event fires.
Recon must confirm it. If it does not, the fallback ladder is: (1) construct a minimal UMG
widget at runtime from Lua, accepting materially more engine work; (2) ship keyboard-only
for v1 and revisit. The fallback is a rendering-layer change only.

## Survey findings (2026-09-27) — these override the original brief's stack

The brief assumed Unity/BepInEx/Harmony. That is wrong.

- **RV There Yet? is Unreal Engine 5.** Developer Nuggets Entertainment, Steam app `3949040`.
- The community mod platform is the Thunderstore community `rv-there-yet`. It has exactly
  6 packages: 2 mod managers, the loader, and 3 actual mods.
- **All three real mods depend on `Thunderstore-unreal_shimloader-1.1.7`**, which is the
  Thunderstore shim around **RE-UE4SS**. There is no BepInEx, no MelonLoader, no Harmony.
- Two conventions exist side by side:
  - **Lua mods** (`mod/scripts/main.lua` + `mod/enabled.txt` + `mod/config.ini`) — e.g. `samlii-MoreRVers`
  - **Blueprint/pak mods** (`pak/*.pak|.ucas|.utoc`) — e.g. `ThisIsNotACNC-FritoBois`
- `MoreRVers` states **"Only the host needs to install the mod."** It changes the player cap
  by writing `MaxPlayers`-family properties on `GameSession`/`GameModeBase`/`GameStateBase`,
  driven from several redundant UE4SS triggers.
- The bundled UE4SS ships `CheatManagerEnablerMod`, `ConsoleEnablerMod`, `ConsoleCommandsMod`,
  `BPModLoaderMod` and `BPML_GenericFunctions` enabled by default.

## Netcode

UE5 listen-server replication. The host is the authority. Mutating a replicated,
server-owned actor on the host propagates to clients through normal replication, so
**clients do not need the mod installed** — consistent with MoreRVers' own README.

Known caveat: `UCharacterMovementComponent` is client-authoritative for the owning
client's pawn. A bare `SetActorLocation` on a remote player's pawn from the host will be
corrected away by the client's next move update. Teleports of remote players must go
through a path that forces a client correction (`ATeleportTo`, `PlayerController::
ClientSetLocation`, or a `ForcePositionUpdate`), verified in-game.

## Constraints

- Loader: RE-UE4SS via `Thunderstore-unreal_shimloader` (declared as a dependency).
- Language: Lua 5.4 (UE4SS's embedded Lua).
- Distribution: Thunderstore package under the `darkharasho` team, community `rv-there-yet`.
- Host-only. Non-host use must detect the lack of authority and refuse.
- No anti-cheat evasion. No use in unwilling or public lobbies.
- No custom art or polished UMG design for v1.

## Out of scope

- Custom art, textures, or fonts. The overlay is flat rectangles and the engine's default font.

- Client-side actions by non-host players
- Detection evasion / griefing tooling
- Custom art assets
