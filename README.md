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
admin menu overlay. The menu is mouse-driven: hover to highlight a row, left-click to
select it.

## Configuration

See `config.ini` in the mod's folder. Every key is documented inline there with its
default and valid values:

| Key | Default | Values |
|---|---|---|
| `Hotkey` | `F3` | `F1`-`F12`, `INSERT`, `HOME`, `END`, `DELETE`, `PAGE_UP`, `PAGE_DOWN` |
| `LogLevel` | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR` |
| `ConfirmDestructive` | `true` | `1`/`true`/`yes`/`on` or `0`/`false`/`no`/`off` |
| `HealAmount` | `100` | `1`-`1000` |

An unrecognized value falls back to the default and logs a warning; the mod never
fails to load because of a bad config line.

## Status

Early scaffold. See `CHANGELOG.md` for what has landed so far.
