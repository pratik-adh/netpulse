#!/bin/bash
#
# Builds "Netpulse.app" from source.
#
#   ./build.sh              build into "./dist/Netpulse.app"
#   ./build.sh --install    build, then move it into /Applications and launch it
#   ./build.sh --universal  build a universal (arm64 + x86_64) binary, for releases
#
# The flags combine, in any order.
#
# Requirements: macOS 13+ and the Xcode Command Line Tools
#               (run `xcode-select --install` once if `swift` is missing).
#
set -euo pipefail

# PRODUCT is the compiled binary (and the SwiftPM target); APP_NAME is what
# people see in Finder and the Dock.
PRODUCT="Netpulse"
APP_NAME="Netpulse"
BUNDLE_ID="com.netpulse.mac"
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

INSTALL=0
UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --install)   INSTALL=1 ;;
    --universal) UNIVERSAL=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "error: 'swift' not found. Install the Xcode Command Line Tools:"
  echo "         xcode-select --install"
  exit 1
fi

# A universal build is what releases ship, so the app runs on both Apple
# silicon and Intel; a plain build stays native-only because it is much faster
# to iterate on.
BUILD_FLAGS=(-c release)
if [ "$UNIVERSAL" = "1" ]; then
  BUILD_FLAGS+=(--arch arm64 --arch x86_64)
  echo "==> Compiling (release, universal arm64 + x86_64)…"
else
  echo "==> Compiling (release)…"
fi

swift build "${BUILD_FLAGS[@]}"

BIN_PATH="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"
APP="dist/$APP_NAME.app"

echo "==> Assembling $APP …"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# ---- app icon -------------------------------------------------------------
if [ -f "Resources/icon_1024.png" ] && command -v iconutil >/dev/null 2>&1; then
  echo "==> Building icon…"
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  gen() { sips -z "$2" "$2" "Resources/icon_1024.png" --out "$ICONSET/icon_$1.png" >/dev/null; }
  gen "16x16"        16
  gen "16x16@2x"     32
  gen "32x32"        32
  gen "32x32@2x"     64
  gen "128x128"     128
  gen "128x128@2x"  256
  gen "256x256"     256
  gen "256x256@2x"  512
  gen "512x512"     512
  gen "512x512@2x" 1024
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# ---- ad-hoc signature ------------------------------------------------------
# Not required to run, but it gives the app a stable identity so macOS
# remembers its permissions and "Open at Login" registration between builds.
if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc signing…"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 || \
    echo "    (signing skipped - the app still runs)"
fi

echo ""
echo "Built: $ROOT/$APP"

if [ "$INSTALL" = "1" ]; then
  echo "==> Installing to /Applications…"
  pkill -x "$PRODUCT" 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
  echo "Running. Look for the usage readout in your menu bar."
else
  echo ""
  echo "Next:  open \"$APP\"     (run it from here)"
  echo "  or:  ./build.sh --install  (move to /Applications and launch)"
fi
