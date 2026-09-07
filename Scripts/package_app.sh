#!/usr/bin/env bash
# Package MoleGUI as a minimal .app bundle (no Xcode project required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
cd "$ROOT"

APP_NAME="MoleUX"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

# The icon is drawn in code (Scripts/make_icon.swift), so it is generated here
# rather than committed as a binary. Regenerate by deleting Assets/AppIcon.icns.
ICON_SRC="$ROOT/Assets/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
  echo "→ Generating app icon…"
  swift "$ROOT/Scripts/make_icon.swift" "$ROOT/Assets"
  iconutil -c icns "$ROOT/Assets/AppIcon.iconset" -o "$ICON_SRC"
fi

echo "→ Building release binary…"
swift build -c release

BIN="$BUILD_DIR/MoleGUI"
if [[ ! -x "$BIN" ]]; then
  BIN="$(swift build -c release --show-bin-path)/MoleGUI"
fi

echo "→ Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

cp "$BIN" "$MACOS/MoleGUI"
chmod +x "$MACOS/MoleGUI"

# Launcher advertises the bundled copy as a *fallback*; the app still prefers a
# real install (Homebrew, ~/.local) and an explicit MOLE_PATH over it.
cat > "$MACOS/$APP_NAME" <<'LAUNCH'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -x "$DIR/../Resources/mole/mole" ]]; then
  export MOLE_BUNDLED_PATH="$DIR/../Resources/mole/mole"
fi
exec "$DIR/MoleGUI" "$@"
LAUNCH
chmod +x "$MACOS/$APP_NAME"

# Copy the workspace CLI into the bundle for offline use. The `mole` entry
# script resolves its own directory and sources `lib/` and `bin/` from there, so
# the whole tree has to travel together — shipping the entry script alone (or
# dropping it *inside* bin/) yields a copy that fails on every subcommand.
if [[ -x "$REPO_ROOT/mole/mole" && -d "$REPO_ROOT/mole/lib" && -d "$REPO_ROOT/mole/bin" ]]; then
  rm -rf "$RES/mole"
  mkdir -p "$RES/mole"
  cp "$REPO_ROOT/mole/mole" "$RES/mole/mole"
  [[ -f "$REPO_ROOT/mole/mo" ]] && cp "$REPO_ROOT/mole/mo" "$RES/mole/mo"
  cp -R "$REPO_ROOT/mole/bin" "$RES/mole/bin"
  cp -R "$REPO_ROOT/mole/lib" "$RES/mole/lib"
  chmod +x "$RES/mole/mole" "$RES/mole/bin/"* 2> /dev/null || true
  [[ -f "$RES/mole/mo" ]] && chmod +x "$RES/mole/mo"

  if MOLE_TEST_OUT=$("$RES/mole/mole" help 2>&1); then
    echo "   bundled a working mole CLI into Resources/mole"
  else
    echo "   WARNING: bundled CLI failed its smoke test:" >&2
    echo "$MOLE_TEST_OUT" | head -3 >&2
  fi
else
  echo "   no workspace CLI at $REPO_ROOT/mole — the app will use an installed mole"
fi

cp "$ICON_SRC" "$RES/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.alecyriaco.moleux</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <!-- Required since 10.14, or the "Terminal UI" buttons are denied silently. -->
  <key>NSAppleEventsUsageDescription</key>
  <string>MoleUX opens Terminal to run the Mole CLI's interactive screens.</string>
  <key>NSSupportsAutomaticTermination</key>
  <true/>
  <key>NSSupportsSuddenTermination</key>
  <true/>
</dict>
</plist>
PLIST

# PkgInfo
echo -n 'APPL????' > "$CONTENTS/PkgInfo"

# Ad-hoc signature — without it macOS kills the bundle once it is copied
# elsewhere ("is damaged"), and the app can't prompt for Full Disk Access.
codesign --force --deep --sign - "$APP_DIR" > /dev/null 2>&1 \
  && echo "→ ad-hoc signed" \
  || echo "→ codesign unavailable, bundle left unsigned" >&2

echo "✓ App ready: $APP_DIR"
echo "  open \"$APP_DIR\""
