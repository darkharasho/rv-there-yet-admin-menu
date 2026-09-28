#!/usr/bin/env bash
# Build a repo-local Lua 5.4 + luarocks + busted into .tooling/prefix.
# Needed only where the system has no Lua 5.4 and no root access.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$ROOT/.tooling/prefix"
SRC="$ROOT/.tooling/src"
LUA_VER=5.4.7
LR_VER=3.11.1

mkdir -p "$SRC" && cd "$SRC"
curl -fsSL -o lua.tar.gz "https://www.lua.org/ftp/lua-$LUA_VER.tar.gz"
curl -fsSL -o luarocks.tar.gz "https://luarocks.org/releases/luarocks-$LR_VER.tar.gz"
tar xzf lua.tar.gz && tar xzf luarocks.tar.gz

cd "$SRC/lua-$LUA_VER"
make linux MYCFLAGS=-fPIC -j4
make install INSTALL_TOP="$PREFIX"

cd "$SRC/luarocks-$LR_VER"
./configure --prefix="$PREFIX" --with-lua="$PREFIX" --lua-version=5.4
make install

"$PREFIX/bin/luarocks" --lua-version=5.4 --tree="$PREFIX" install busted
rm -rf "$SRC"
echo "Toolchain ready. Run tests with scripts/test.sh"
