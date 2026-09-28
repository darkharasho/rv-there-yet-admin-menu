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

See `config.ini` in the mod's folder. Today it ships a single `Hotkey` key (default
`F3`); more settings will be documented there, inline with their defaults and valid
ranges, as they are added.

## Status

Early scaffold. See `CHANGELOG.md` for what has landed so far.
