# Static recon — 2026-10-29

Read from the installed game (build `RideInc-release-1.4`, UE 5.6) without running it:
`strings` on `Ride-Win64-Shipping.exe`, `retoc list` / `retoc to-legacy` on
`Content/Paks`, and the name tables of the converted Blueprints. Names below are
quoted from those sources. Parameter lists are not confirmed yet; they come from
the `GenerateSDK()` dump in `tools/dump-game-objects.lua`.

## Engine and loader
- Unreal Engine 5.6, listen server. Game C++ module `/Script/Ride`, class prefix `RG`.
- Mods load through `unreal_shimloader` (RE-UE4SS), which r2modman installs into the
  game folder (`dwmapi.dll`, `ue4ss.dll`). Mods go in the profile's `shimloader/mod/<Name>/`.

## Classes (from the game log and paks)
- Player pawn: `/Game/Ride/Character/Blueprints/BP_FirstPersonCharacter.BP_FirstPersonCharacter_C`
- Controller: `BP_FirstPersonPlayerController_C` (C++ base `ARGPlayerController`)
- Player state: `BP_PlayerState_C` (C++ base `RGPlayerState`)
- Game mode: `GM_FirstPerson_C`; game state: `/Game/Ride/Game/RideGameState.RideGameState_C`
- RV: `BP_Vehicle_Winnebago_C` (C++ base `RGWheeledVehiclePawn`)
- Checkpoint: `/Game/Ride/Game/BP_CheckPoint`
- Revive station: `/Game/Ride/Interactables/ReviveStation/BP_Interactable_ReviveStation`
- Items: `BP_Interactable_*` under `/Game/Ride/Interactables/` (base `BP_Interactable_Actor`)
- Spectating while dead: `BP_SpectatorCameraActor_C`
- Maps: `/Game/Ride/Maps/Frontend_Jungle` (menu), `SnowLevel`, `TransitionMap`, jungle level

## RGCheatManager (C++) exec functions
`GiveItem(ItemClass)`, auto-registered `GiveItem_<item>` ("Spawns %s in front of the player"),
`GodPlayers`, `GodVehicles`, `DumpOverlaps`, `Golf_*`. BP event `ReceiveGiveItem`.

## C++ character-facing functions (interface / library)
`IsDead`, `IsRagdolling`, `IsRagdolled`, `GetCurrentPickedUpActor`, `GetCurrentDamageTaken`,
`TeleportPlayerTo`, `ReceiveSetRagdolled`, `ReceiveSetNewMaxWalkSpeed`,
`ReceiveSetNewJumpVelocity`, `IsPlayerPassenger`, `SetSwimEnabled`.

## BP_FirstPersonCharacter_C names (name table)
- Revive: `ForceRevive`, `Revive`, `ServerReviveTarget` (`PlayerToRevive`),
  `Server_RevivePlayerAtLocation` (`PlayerToRevive`, `NewLocation`),
  `RevivePlayerSafelyAtLocation`, `Client_MovePlayerAfterRevive`, `Multicast_PlayReviveAnim`
- Death and damage: `IsPlayerDead`, `Client_OnPlayerDied`, `Server_TakePlayerDamage`,
  `Internal_TakePlayerDamage` (`DamageResults`, `Killbox`), `DeathDamageThreshold`,
  `CurrentDamage`, `TotalDamageTaken`
- Heal: `Server_HealPlayerDamage` / `Internal_HealPlayerDamage` (`DamageToHeal` struct)
- God / tuning: `Server_UpdateInvulnerable` (`Invulnerable`), `Server_UpdateSpeedMultiplier`
  (`NewSpeedMultiplier`), `Server_UpdateStrengthMultiplier` (`NewStrengthMultiplier`)
- Holding / grabbing: `CurrentPickUpActor`, `Current3rdPersonPickUpActor`, `Server_DropActor`,
  `Internal_DropActor`, `TryToClearPickedUpActor`, `TryDropIfItemIsHeld`, `Server_PickUpActor`,
  `CheckForMonkeyGrab` (monkeys grab players too)
- Ragdoll: `SetRagdoll`, `Server_Ragdoll`, `IsRagdoll`, `OnRep_IsRagdoll`
- Seats: `Client_ForceUnseat`, `Server_SitOnRideableActor`, `SetInsideRV`, `IsInsideRV`
- Spawning: `SpawnAndPickupInteractable`, `Server_SpawnInteractableAttachedToPlayer`
- Teleport: `K2_TeleportTo`, `TeleportByRocket`
- Spectate: `SpectateAnotherPlayer`, `StopSpectating`

## Still open (needs one in-game F9 dump)
Exact parameter lists, whether `ReceiveDrawHUD` fires (menu rendering), checkpoint
ordering, and how a grabbed player is attached to the grabber or a monkey.
