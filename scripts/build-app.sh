#!/bin/bash
# Builds Wisp.app from the SPM binary — no Xcode required.
#   ./scripts/build-app.sh            build into ./build/Wisp.app
#   ./scripts/build-app.sh --install  also copy to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Wisp"
BUNDLE_ID="com.arthurhinton.wisp"
VERSION="1.0.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compiling (release)…"
swift build -c release

if [ ! -f Resources/AppIcon.icns ]; then
  echo "▸ Generating app icon…"
  swift scripts/make-icon.swift
fi

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>                <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>         <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>CFBundleShortVersionString</key>  <string>$VERSION</string>
    <key>CFBundleVersion</key>             <string>$VERSION</string>
    <key>CFBundleIconFile</key>            <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>      <string>26.0</string>
    <key>NSHighResolutionCapable</key>     <true/>
    <key>NSPrincipalClass</key>            <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key> <string>Wisp listens while you hold the dictation key.</string>
    <key>NSSpeechRecognitionUsageDescription</key> <string>Wisp turns your speech into text on this Mac.</string>
</dict>
</plist>
PLIST

echo "▸ Codesigning (ad-hoc, stable identity)…"
# A plain ad-hoc signature changes on every rebuild, which makes macOS treat
# each build as a new app and drop its Screen Recording grant. Pinning the
# designated requirement to the bundle identifier keeps TCC permissions
# stable across rebuilds. (Personal-use tradeoff: identity is name-based,
# not certificate-based.)
codesign --force --sign - \
  --identifier "$BUNDLE_ID" \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP"

echo "✓ Built $APP"

if [ "${1:-}" = "--install" ]; then
  echo "▸ Installing to /Applications…"
  # Quit a running copy so the binary can be replaced.
  osascript -e 'tell application "Wisp" to quit' >/dev/null 2>&1 || true
  sleep 0.5
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "✓ Installed. Launching…"
  open "/Applications/$APP_NAME.app"
fi
