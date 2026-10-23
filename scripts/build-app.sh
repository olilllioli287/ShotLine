#!/bin/bash
# Builds ShotLine.app into ./build without needing Xcode.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/ShotLine.app"
VERSION="1.7.3"

# Builds one architecture and prints the binary's path.
# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include. If the default SDK fails, fall back to the
# newest macOS 26 SDK installed alongside it.
build_arch() {
  local triple="$1-apple-macosx14.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple" >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --triple "$triple" >&2; fi
  cp "$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)/ShotLine" "$OUT/ShotLine-$1"
}

# A universal binary, so it runs on Apple silicon and on Intel Macs, from
# macOS 14 Sonoma onwards.
OUT="$(mktemp -d)"
build_arch arm64
build_arch x86_64
lipo -create "$OUT/ShotLine-arm64" "$OUT/ShotLine-x86_64" -output "$OUT/ShotLine"
BIN="$OUT/ShotLine"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ShotLine"

# Icon
WORK="$(mktemp -d)"
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/ShotLine.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ShotLine.icns"
rm -rf "$WORK"

# Translations: one folder per language, listed in Info.plist so macOS knows
# which languages the app speaks.
LANGUAGES=""
for dir in Sources/ShotLine/Resources/*.lproj; do
  cp -R "$dir" "$APP/Contents/Resources/"
  LANGUAGES="$LANGUAGES<string>$(basename "$dir" .lproj)</string>"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ShotLine</string>
  <key>CFBundleDisplayName</key><string>ShotLine</string>
  <key>CFBundleIdentifier</key><string>local.shotline.ShotLine</string>
  <key>CFBundleExecutable</key><string>ShotLine</string>
  <key>CFBundleIconFile</key><string>ShotLine</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>11</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>${LANGUAGES}</array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>ShotLine watches the folder where macOS saves your screenshots so it can hang them on the line.</string>
  <key>NSDocumentsFolderUsageDescription</key>
  <string>ShotLine watches the folder you chose so it can hang new images on the line.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>ShotLine watches the folder you chose so it can hang new images on the line.</string>
</dict>
</plist>
PLIST

# Sign with a Developer ID when one is in the keychain (or SIGN_IDENTITY is
# set), with the hardened runtime and a secure timestamp that notarization
# requires. Without one, use a fixed local certificate if there is one
# (LOCAL_SIGN_IDENTITY, by default the self-signed "Toolbox Local Signing"):
# an ad hoc signature changes with every build, so macOS treats each build as
# a new app and asks for Desktop access again. Only then sign ad hoc.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
LOCAL_IDENTITY="${LOCAL_SIGN_IDENTITY:-Toolbox Local Signing}"
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  echo "Signed with $IDENTITY"
elif security find-identity -p codesigning 2>/dev/null | grep -qF "\"$LOCAL_IDENTITY\""; then
  codesign --force --sign "$LOCAL_IDENTITY" "$APP"
  echo "Signed with $LOCAL_IDENTITY"
else
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Signed ad hoc (no Developer ID found)"
fi
echo "Built $APP"
