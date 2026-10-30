# Changelog

## 0.2.12

- Fix: god mode wore off. The game's invulnerability is a timed buff, so god mode (me,
  a player, or everyone) is now re-applied every second until you switch it off.
- Heal: damage tags are rebuilt from their names, the heal is sent through both the
  character and the controller, and the log records the damage entries it found.

## 0.2.11

- Spawn item shows a search field under the title: "Type to search..." until you type,
  then your text with a cursor.
- Fix: the nitroglycerin bottle still dropped at your feet; the item list lost its
  "into your hands" flag.
- The host check logs more detail (pawn role, IsServer) when it decides you are a client.

## 0.2.10

- Spawn item: type to search. Letters, digits and space filter the list as you type
  (every word must match); Backspace erases, and with nothing typed goes back.
- Fix: the nitroglycerin bottle exploded at your feet when spawned. It now goes straight
  into your hands.

## 0.2.9

- Fix: Players (and other host actions) said "Host only" for the host. The check looked
  for a game mode by an exact class name the game doesn't use; it now also tries the
  game's own game-mode names and the local pawn's network authority, and logs the result.
- Fix: God mode for yourself now uses the cheat, the pawn call and the property together,
  and logs whether it stuck.

## 0.2.8

- Fix: opening Spawn item crashed the game. The item list no longer walks every object in
  memory; it's a fixed list of 47 pickups (tools, food, epipens, dynamite, ...) and each
  class is found or loaded by path when you spawn it.
- Fix attempt: the Players page came up empty. The validity check no longer treats an
  object it can't query as dead, and the log records how many player pawns were found and
  why any were skipped.

## 0.2.7

- Unseat now finds the actual seat (car seats included) and reads that seat's own seat
  type. Your own pawn stands up the same way the unmount key does; other players get the
  game's forced exit. If you're attached to the RV itself, the nearest seat is used.
- New: Me > Unseat me.
- The log no longer fills with GetPlayerName warnings for leftover bodies.

## 0.2.6

- Fix: Force unseat left the seat permanently unusable. It now only triggers the game's
  own forced exit (`Client_ForceUnseat`) instead of also clearing the seat with a guessed
  seat type and detaching the player by force.

## 0.2.5

- New look: dark rounded panel, orange accent bar on the selected row, smaller text, ">"
  for submenus, coloured ON/OFF for toggles, red Kill, and a key hint footer.
- Fix: Kill (and other player actions) could hit a dead player's leftover body after a
  revive. Validity checks were always true because UE4SS has no global `IsValid`.
- Fix: "no item list available". Release builds leave the cheat item registry empty, so
  the list now comes from every loaded item class.

## 0.2.4

- Fix: every game function call failed with "no such function" (UE4SS returns them as
  callable userdata). This broke player names, positions, kill, teleports and mouse capture.
- Player names fall back to the raw `PlayerNamePrivate` field.
- Every page ends with a clickable "< Back" row ("Close" on the main page).

## 0.2.3

- Fix: the menu panel was built but its text failed to set. UE4SS `FName`/`FText` are
  userdata that do not expose `__call`, so they were treated as missing.

## 0.2.2

- Fix: the overlay still could not see UE4SS's globals. Look them up through `_G`
  normally instead of `rawget`, and build widgets without names if `FName` is missing.
- Log the type of each UE4SS global at startup.

## 0.2.1

- Fix: the on-screen menu never appeared. UE4SS provides `FName`/`FText` as callable
  objects, not plain functions, and the global check rejected them.

## 0.2.0

- Mouse support (untested in game): while the menu is open the cursor is shown and the
  controller switches to UI-only input (camera and clicks no longer reach the game).
  Hover selects a row, left click = Enter, right click = Back, Esc closes the menu.
- Menu is now a row-per-item widget with a highlighted selection instead of one text block.
- New `Mouse = true` option in `config.ini`; `false` restores the v0.1 keyboard-only behaviour.

## 0.1.0

- First in-game test build: keyboard-driven UMG menu with teleport (RV, checkpoints, bring),
  per-player and everyone actions (revive, heal, kill, free, unseat, god, speed), self
  actions and item spawning. Host-only gating for actions on other players.
- Fixed hotkey names (`INS`, `DEL`); package zip now has the mod contents at its root.

- Initial repo skeleton: Thunderstore package layout, `manifest.json`, and a minimal
  `mod/scripts/main.lua` that loads and logs `[RVAdminMenu] v0.1.0 loaded`.
