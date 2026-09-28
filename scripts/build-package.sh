#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -oP '"version_number":\s*"\K[^"]+' manifest.json)
out="dist/RVAdminMenu-${version}.zip"
mkdir -p dist && rm -f "$out"
zip -r "$out" manifest.json icon.png README.md mod/ -x '*.DS_Store'
echo "built $out"
