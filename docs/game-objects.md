# Game object recon — RV There Yet?

> **STATUS: TEMPLATE. NO RECON HAS BEEN RUN YET.**
>
> Every section below is an empty, explicitly unverified placeholder. No
> class name, property name, function name, or `/Script/...` / `/Game/...`
> path in this document has been confirmed against the running game — this
> doc was written on a Linux dev machine with no game install and no live
> 2-player session available. Every later task that reads this doc (Tasks
> 6, 9, 10, 11, 12, and `mod/scripts/lib/ue.lua`'s `ASSUMED` table) MUST
> treat every answer here as unanswered until a human runs the recon tool
> described below and fills in each section with data quoted verbatim from
> the dump. Do not let any agent or task guess a plausible-looking value to
> fill a gap — a fabricated path here silently poisons every task that
> reads it as canonical.

## 1. Player pawn/character class and health properties

**Question:** The player pawn/character class and its health-bearing
properties (health, max health, downed/dead flag).

**Grep terms:** class names from the `pawn` / `character` sections of the
dump; property names containing `Health`, `Max`, `Down`, `Dead`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Task 6 (health/revive/kill actions) cannot
target the correct class or properties and cannot be implemented safely.

## 2. Player controller and player state classes, and display name property

**Question:** The player controller and player state classes, and which
property holds the display name.

**Grep terms:** class names from the `controller` / `playerstate` sections
of the dump; property names containing `Name`, `DisplayName`, `PlayerName`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Any task that needs to list connected players by
name (player picker UI, targeting) has no confirmed source for the label
and cannot be implemented.

## 3. Death and revive functions

**Question:** The function(s) that run on death and on revive.

**Grep terms:** `Revive`, `Down`, `Die`, `Respawn`, `Damage`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Task 6's revive/kill actions have no confirmed
entry point and risk calling a function that doesn't exist or has
different semantics than assumed.

## 4. Checkpoint actor class and self-identification

**Question:** The checkpoint actor class — and how a checkpoint identifies
itself (index? name? tag?).

**Grep terms:** `Checkpoint`, `Respawn`, `Spawn`, `Milestone`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Task 9 (warp to checkpoint) has no confirmed
class to enumerate or field to key a checkpoint list off of, and cannot be
implemented.

## 5. Spawnable item base class and concrete Blueprint classes

**Question:** The spawnable item base class — and the set of concrete
Blueprint classes under `/Game/`.

**Grep terms:** `Pickup`, `Item`, `Consumable`, `Prop`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Task 10 (spawn arbitrary items) has no confirmed
base class to spawn against and no confirmed list of spawnable Blueprint
paths, and cannot be implemented.

## 6. CheatManager availability and working functions

**Question:** Whether the game exposes a CheatManager (the loader ships
`CheatManagerEnablerMod` enabled), and which of `God` / `Teleport` /
`Summon` actually work.

**Grep terms:** `CheatManager`, `God`, `Teleport`, `Summon`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Tasks that would otherwise shortcut through
built-in cheat commands (rather than reimplementing teleport/spawn/god
logic by hand) cannot rely on that shortcut and must fall back to manual
property/function manipulation confirmed by questions 1–5.

## 7. Host authority detection

**Question:** How the host distinguishes itself: which property or
function reports authority (`HasAuthority`, `GetLocalRole`, `IsServer`).

**Grep terms:** `HasAuthority`, `GetLocalRole`, `IsServer`.

**Answer:** **UNVERIFIED — fill from the dump**

**If unanswered / wrong:** Every task that must act authoritatively on
other players (revive, kill, teleport, item spawn on someone else's pawn)
has no confirmed way to gate host-only behavior, risking the mod running
unauthoritative logic on a non-host client.

## 8. AHUD subclass and whether ReceiveDrawHUD fires

**Question:** Is there an `AHUD` subclass, and does its draw event fire?
Record the class path, and confirm by hooking it — **the menu's entire
rendering approach depends on this answer.** If it fires, also confirm
`DrawRect` and `DrawText` are callable on the HUD object from inside the
hook.

**Grep terms:** `HUD` (in the dump); hook target
`/Script/Engine.HUD:ReceiveDrawHUD` (already wired in
`tools/dump-game-objects.lua`, throttled to the first 5 fires so it can't
flood `UE4SS.log`).

**Answer:** **UNVERIFIED — fill from the dump**

**DrawRect / DrawText callable from the hook:** **UNVERIFIED — fill from the dump**
(Answered by the two `[recon] ReceiveDrawHUD: type(hud.DrawRect) = ...` and
`[recon] ReceiveDrawHUD: type(hud.DrawText) = ...` lines that
`tools/dump-game-objects.lua` prints on the hook's first fire only. A
value of `function` means it is callable; anything else (`nil`, `table`,
etc.) means it is not.)

**This is the single most important question in this recon.** If
`ReceiveDrawHUD` never fires, the plan's IMGUI-via-HUD-hook rendering
approach is dead and Task 8 must take the documented fallback ladder
instead:
1. Construct a minimal UMG widget from Lua, or
2. Ship keyboard-only for v1 (no overlay rendering at all).

Do not proceed with Task 8 as currently planned until this section is
filled in and confirms the hook fires.

## 9. Mouse plumbing on the local PlayerController

**Question:** Confirm `bShowMouseCursor` is writable, and which of
`GetMousePosition` / `WasInputKeyJustPressed` / `IsInputKeyDown` are
callable. Record the current value of `bShowMouseCursor` during normal
play — Task 8 must restore it, not just set it.

**Grep terms:** `GetMousePosition`, `WasInputKeyJustPressed`,
`IsInputKeyDown`, `bShowMouseCursor` (in the `controller` section of the
dump).

**Answer:** **UNVERIFIED — fill from the dump**

**`bShowMouseCursor` writable:** **UNVERIFIED — fill from the dump**

**Callable functions among `GetMousePosition` / `WasInputKeyJustPressed` /
`IsInputKeyDown`:** **UNVERIFIED — fill from the dump**

**`bShowMouseCursor` value during normal play:** **UNVERIFIED — fill from the dump**

**Cross-reference:** `mod/scripts/lib/ue.lua` already contains an
`ASSUMED` table (`mouse_position_fn = "GetMousePosition"`,
`mouse_down_fn = "IsInputKeyDown"`, `left_mouse_key = "LeftMouseButton"`,
`cursor_visible_prop = "bShowMouseCursor"`) built entirely from guesses
awaiting exactly this recon. Once this section is answered, confirming or
correcting question 9 means editing that one `ASSUMED` table in
`mod/scripts/lib/ue.lua` — no other file needs to change for this
correction to take effect.

**If unanswered / wrong:** Task 8 (mouse-driven menu interaction) is built
on unverified guesses and may silently fail to move the cursor, detect
clicks, or restore the player's cursor state after closing the menu.

## 10. UE4SS `Key` table names for the configurable hotkey

**Question:** Dump UE4SS's global `Key` table and record the exact spelling
of every key name the mod advertises as a valid `Hotkey` value:
`F1`-`F12`, `INSERT`, `HOME`, `END`, `DELETE`, `PAGE_UP`, `PAGE_DOWN`.
For each one, record whether the name exists in the table verbatim and, if
not, what the actual spelling is (abbreviated forms such as `INS`, `DEL`,
`PAGEUP`, `PAGE_UP`, `PRIOR`/`NEXT` are all plausible and only the dump can
settle it).

**Grep terms:** `[recon] Key name:` in `UE4SS.log` — the sorted list that
`tools/dump-game-objects.lua` prints for every name in the `Key` table on
each F9 dump.

**Answer:** **UNVERIFIED — fill from the dump**

**Names confirmed present verbatim:** **UNVERIFIED — fill from the dump**

**Names that differ, with their actual spelling:** **UNVERIFIED — fill from the dump**

**Cross-reference:** `mod/scripts/lib/config.lua`'s `M.KEY_NAMES` is the
list the mod accepts from `config.ini`, and `mod/config.ini` and
`README.md` document those same names to the user as supported. The
function-key names (`F1`-`F12`) are near-certain; the six non-function
names are guesses. `mod/scripts/lib/ue.lua`'s `bind_key` refuses to
register a name that UE4SS's `Key` table does not contain and warns
instead, so a wrong spelling here is a visible warning rather than a
hotkey that silently never fires — but the user still cannot bind that
key until this section is answered. Do not guess at corrections; copy the
spellings from the dump.

**If unanswered / wrong:** A user who sets `Hotkey = DELETE` (a value
`config.ini` tells them is valid) gets a refused binding and a warning in
`UE4SS.log`, and has no working way to open the menu on that key.

## How to run this recon

1. Install `tools/dump-game-objects.lua` as its own UE4SS mod, separate
   from the shipped RVAdminMenu package:
   - Copy the file to `<UE4SS mods dir>/RVRecon/scripts/main.lua`.
   - Create an (empty is fine) `<UE4SS mods dir>/RVRecon/enabled.txt`.
2. Launch the game with UE4SS and this mod enabled.
3. Host a session with a second player connected — several of the
   questions above (display name, authority, revive/kill) only make sense
   with two players present.
4. Press **F9** in-game to trigger the dump.
5. Collect two files:
   - `UE4SS.log` (next to `UE4SS.dll` / the game executable)
   - `ObjectDump.txt` (also written next to `UE4SS.dll`, produced by
     `DumpAllObjects()`)
6. For each section above, search both files with the listed grep terms
   and fill in the answer by quoting the dump verbatim — exact class
   paths, exact property/function names. Do not paraphrase or "clean up"
   a path; copy it exactly as it appears in the dump.
7. Once every section is filled in, replace the status banner at the top
   of this file to say recon is complete, and update
   `mod/scripts/lib/ue.lua`'s `ASSUMED` table per question 9's findings.
