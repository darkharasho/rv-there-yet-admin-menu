# RVAdminMenu

A hotkey-summonable, host-only admin/cheat menu for *RV There Yet?* co-op sessions. The
host opens an in-game overlay to spawn items, revive/kill/heal/teleport any player in the
session, and warp to specific checkpoints.

This mod is intended for **private lobbies with consenting players only**. It is a
host-side convenience/cheat tool, not a competitive-integrity or anti-cheat-evasion tool,
and must not be used in unwilling or public lobbies.

## Requirements

- [`unreal_shimloader`](https://thunderstore.io/c/rv-there-yet/) (RE-UE4SS shim), installed
  automatically as a dependency by most mod managers.

## Installation

Install via [r2modman](https://thunderstore.io/package/ebkr/r2modman/) or
[Gale](https://thunderstore.io/package/Kesomannen/GaleModManager/) into an *RV There Yet?*
profile alongside `unreal_shimloader`.

**Only the host needs to install this mod.** *RV There Yet?* uses Unreal Engine 5's
listen-server replication: the host is the authority, so host-side actions taken through
this menu propagate to every client in the session automatically. Clients do not need the
mod installed.

## Usage

Press the configured hotkey (default `F3`, rebindable in `config.ini`) to toggle the
menu. Keyboard and mouse both work:

| Key | Action |
|---|---|
| `F3` (configurable) | Open / close the menu |
| Up / Down arrow | Move the selection |
| Enter or Right arrow | Select / open a submenu |
| Backspace or Left arrow | Go back (closes the menu at the top level) |

| Mouse hover | Select the row under the cursor |
| Left click | Select (same as Enter) on the hovered row; clicking empty space does nothing |
| Right click | Go back (closes the menu at the top level) |
| `Esc` | Close the menu |

While the menu is open the mouse cursor is shown and the game is switched to UI-only
input, so the camera does not turn and clicks do not reach the world; everything is
restored when the menu closes. Set `Mouse = false` in `config.ini` for keyboard-only
behaviour (no cursor, no input-mode change, no mouse binds).

The navigation keys do nothing while the menu is closed. Destructive actions (Kill,
Restart at checkpoint) ask for confirmation: press Enter again to confirm.

### Features

- **Teleport:** me to the RV, everyone to the RV, me to checkpoint 0-15, everyone to a
  loaded checkpoint, restart at checkpoint, bring everyone to me, bring the RV to me.
- **Players** (host only): per player, teleport to me / me to them / send to the RV,
  revive, heal, kill, free from a grab, force unseat, god mode, speed x2.
- **Everyone** (host only): revive all, heal all, free all from grabs, god mode all.
- **Me:** god mode, revive me, heal me, give 5 epipens.
- **Spawn item:** a fixed list of pickups, 15 per page. Type to search (letters, digits,
  space); Backspace erases.

Actions on yourself work for clients too; anything that affects other players needs the
host and otherwise shows "Host only".

## Configuration

See `config.ini` in the mod's folder. Every key is documented inline there with its
default and valid values:

| Key | Default | Values |
|---|---|---|
| `Hotkey` | `F3` | `F1`-`F12`, `INS`, `HOME`, `END`, `DEL`, `PAGE_UP`, `PAGE_DOWN` |
| `LogLevel` | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `ConfirmDestructive` | `true` | `1`/`true`/`yes`/`on` or `0`/`false`/`no`/`off` |
| `HealAmount` | `100` | `1`-`1000` |
| `Mouse` | `true` | `1`/`true`/`yes`/`on` or `0`/`false`/`no`/`off` |

An unrecognized value falls back to the default and logs a warning; the mod never
fails to load because of a bad config line.

## Status

v0.2 is an in-game test build: the engine calls have not all been confirmed in a live
session yet. Check `UE4SS.log` if something does nothing. See `CHANGELOG.md`.
