#!/usr/bin/env bash
# Run the test suite with the repo-local Lua 5.4 toolchain.
# Bootstrap that toolchain with scripts/bootstrap-toolchain.sh if .tooling/ is absent.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="$ROOT/.tooling/prefix"

if [ -x "$PREFIX/bin/busted" ]; then
  export PATH="$PREFIX/bin:$PATH"
  eval "$("$PREFIX/bin/luarocks" --lua-version=5.4 --tree="$PREFIX" path)"
  exec "$PREFIX/bin/busted" "$@"
fi

# CI and systems with a packaged Lua 5.4 use busted from PATH.
command -v busted >/dev/null || {
  echo "busted not found; run scripts/bootstrap-toolchain.sh" >&2
  exit 1
}
exec busted "$@"
