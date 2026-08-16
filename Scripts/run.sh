#!/usr/bin/env bash
# Build and launch Mole GUI (SwiftPM executable).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

# Prefer workspace mole binary for development.
if [[ -x "$REPO_ROOT/mole/mole" ]]; then
  export MOLE_PATH="$REPO_ROOT/mole/mole"
elif [[ -x "$REPO_ROOT/mole/bin/status-go" ]]; then
  # status-go alone is not enough; still try mole script
  :
fi

echo "→ Building MoleGUI…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/MoleGUI"
echo "→ Launching $BIN"
echo "   MOLE_PATH=${MOLE_PATH:-"(auto)"}"
exec "$BIN"
