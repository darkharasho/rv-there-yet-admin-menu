# Game object recon: RV There Yet?

> **STATUS: FILLED from an in-game dump on 2026-10-30** (build `RideInc-release-1.4`,
> UE 5.6, SnowLevel, 4 players, dump taken as a **client**, not the host).
> Signatures come from UE4SS `GenerateSDK()` (CXXHeaderDump). Backups of the dump
> live in `~/.cache/rv-recon/dump/` (headers, `.usmap`, `UE4SS.log`, ObjectDump).
> Names are confirmed to exist. Whether each call *works* when the host calls it
> on another player is still untested; see "Open" at the end.

## 1. Player character and health
- Class: `BP_FirstPersonCharacter_C` (`/Game/Ride/Character/Blueprints/BP_FirstPersonCharacter`),
  C++ base `ARGFirstPersonCharacter` → `AClientAuthoritativeCharacter` → `ACharacter`.
- Health is damage taken, not HP: `int32 GetCurrentDamageTaken()`, properties
  `CurrentDamage`, `DeathDamageThreshold`, `TotalDamageTaken`. `bool IsDead()`.
- God mode: property `Invulnerable` (bool); `Server_UpdateInvulnerable(bool Invulnerable)`.
- Damage struct `FST_Damage_Results { TArray<FST_Damage_Result> DamageResults_3_42A8… }`,
  each `FST_Damage_Result { FGameplayTag DamageType_3_…; int32 Damage_7_…; int32 MaxVehicleShieldConsumption_10_…; bool SkipVehicleShield_12_… }`
  (field names carry BP GUID suffixes; see `ST_Damage_Result.hpp`).
- Other pawns present in the world: `BP_Monster_C` (snow monster), `BP_Goat_C`,
  `BP_Vehicle_Winnebago_01_C`.

## 2. Controller, player state, display name
- Controller `BP_FirstPersonPlayerController_C` (base `ARGPlayerController`). Only the
  local one exists on a client; the host sees all of them.
- Player state `BP_PlayerState_C` (base `ARGPlayerState` → `APlayerState`); one per player.
- Display name: `APlayerState.PlayerNamePrivate` (FString); also `GetPlayerName()`.

## 3. Death, revive, heal, kill
On `BP_FirstPersonCharacter_C`:
- `ServerReviveTarget(PlayerToRevive, bool ForceRevive, bool NoCost, Instigator)`
- `Server_RevivePlayerAtLocation(PlayerToRevive, FVector Location)`
- `RevivePlayerSafelyAtLocation(PlayerToRevive, FVector NewLocation, const FST_Damage_Results& DamageToHeal)`
- `Client_MovePlayerAfterRevive(FVector NewLocation)`, `Client_OnPlayerDied()`
- `Server_HealPlayerDamage(TargetPlayer, const FST_Damage_Results& DamageToHeal)`
- `Server_TakePlayerDamage(TargetPlayer, FST_Damage_Results, bool Killbox)`; kill = large damage or `Killbox=true`.
- Controller also has `Server_HealPlayer(ActorTarget, FST_Damage_Results)`.

## 4. Checkpoints
- `BP_CheckPoint_C`, identified by `int32 CheckpointIndex`; `bool Triggered`;
  `TriggerCheckpoint()`, `GetPlayerStartActor(Controller, out PlayerStart)`.
- None were loaded on SnowLevel at dump time (`FindAllOf` returned none), so
  checkpoints stream in. Warp through the cheat manager instead (section 6).
- Game state `RideGameState_C` has `int32 CurrentCheckpoint`.

## 5. Items
- Base `BP_Interactable_Actor_C` (C++ `ARGInteractableActor`), classes under
  `/Game/Ride/Interactables/`. Full list in the pak listing / ObjectDump.
- Spawn paths: `RGCheatManager.GiveItem(TSubclassOf<ARGInteractableActor>)`,
  `BP_CheatManager_C.SpawnItemInFrontOfPlayer(Class)`,
  controller `Server_SpawnItem(Class, FVector SpawnLocation)`,
  `Server_CheatSpawnAndAttach(Class)`, character `Server_SpawnInteractableAttachedToPlayer(TSoftClassPtr)`.
- Counters: character `Server_UpdateEpiPenCount(int32)`, `Server_UpdatePartsCount(int32)`.

## 6. Cheat manager
Present: `BP_CheatManager_C` (base `URGCheatManager`) on the local controller, created
by the bundled `CheatManagerEnablerMod`. Useful functions:
`RevivePlayer()`, `TeleportToCheckpoint(int32)`, `RestartAtCheckpoint(int32)`,
`TeleportToVehicle()`, `GodPlayers(bool)`, `GodVehicles(bool)`, `GiveItem(Class)`,
`GiveEpiPens(int32)`, `GivePart(int32)`, `DamageAllPlayers(int32)`, `DamageOneClientPlayer(int32)`,
`RepairEngineDamage/RepairWheelDamage/RepairFrameDamage(int32)`, `SaveGame()`,
`RemoveInactivePlayers()`, `IsAnyPlayerAttachedToActor(Actor, out bool)`,
`Unlock{Jungle,Snow,Mabutts}LevelStartingCheckpoint(int32)`. These act on the *local*
player; per-target actions use the character functions above.

## 7. Host authority
- On a client: no `GameModeBase` instance (dump shows none) and one controller.
- Detect host with `FindFirstOf("GameModeBase")` ≠ nil, or `HasAuthority()` on the local pawn.
- **Movement is client-authoritative** (`AClientAuthoritativeCharacter`,
  `ClientAuthoritativeMove`). Moving another player from the host must go through a
  `Client_*` RPC on their pawn (`Client_MovePlayerAfterRevive(FVector)`,
  `Client_LaunchCharacter`), not `K2_TeleportTo` on the server.
- Best teleport candidate: C++ `ARGFirstPersonCharacter::TeleportPlayerTo(const FVector&, const FRotator&)`,
  the game's own teleport for this movement model. The cheat manager's teleports are
  local-player only (`TeleportToCheckpoint`, `RestartAtCheckpoint`, `TeleportToVehicle`);
  `Golf_TeleportAllTo{Tee,Green,Flag}` move everyone but only in the golf level, which
  shows the C++ side can move remote players.

## 8. HUD and ReceiveDrawHUD
- HUD class is plain `/Script/Engine.HUD` (`HUD_0`), no Blueprint subclass.
- `ReceiveDrawHUD` **never fired** (0 fires logged). The HUD canvas path is dead.
- Menu must be UMG built from Lua, or keyboard-driven with on-screen text.

## 9. Mouse plumbing
Confirmed on `APlayerController`: `bool GetMousePosition(float& X, float& Y)`,
`bool IsInputKeyDown(FKey)`, `uint8 bShowMouseCursor`. `ue.lua` `ASSUMED` names are right.

## 10. UE4SS Key names
165 names. Note `INS` and `DEL` (not INSERT/DELETE); `HOME`, `END`, `PAGE_UP`,
`PAGE_DOWN`, `F1`–`F24`, `NUM_ZERO`–`NUM_NINE` exist. `config.lua` KEY_NAMES needs
INSERT→INS, DELETE→DEL.

## Freeing a grabbed player
- Player-held-by-player: the holder's `CurrentPickUpActor` / `Current3rdPersonPickUpActor`
  is the held pawn. Free with holder `Server_DropActor(HeldActor, 0, false, …)` or
  `TryToClearPickedUpActor(Actor)`; `IsPlayerAttachedToThisPlayer(Player, out bool)` to check.
- Monster/seat grabs: the player is seated on a "rideable" (`SetIsPassenger`, `OnPlayerSit`
  on the monster). Free with victim `Client_ForceUnseat(RideableActor)` or
  `Server_SitOnRideableActor(Rideable, false, SeatType)`. Monkeys: `CheckForMonkeyGrab`.
- Ragdoll recovery: `Server_Ragdoll(bool)`.

## Open (needs a host test)
- Whether each `Server_*` call made by the host on another player's pawn takes effect.
- Teleport of a live remote player via `Client_MovePlayerAfterRevive`.
- Building a UMG widget from Lua in this build.
