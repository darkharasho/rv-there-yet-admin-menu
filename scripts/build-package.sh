#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(grep -oP '"version_number":\s*"\K[^"]+' manifest.json)
out="dist/RVAdminMenu-${version}.zip"
mkdir -p dist && rm -f "$out"
# The zip root holds manifest.json, icon.png, README.md and the CONTENTS of
# mod/ (config.ini, enabled.txt, scripts/): HML extracts the zip into
# shimloader/mod/<Name>/ and UE4SS loads <Name>/scripts/main.lua.
zip -j "$out" manifest.json icon.png README.md
(cd mod && zip -r "../$out" . -x '*.DS_Store')
echo "built $out"
