#!/bin/sh
# Build Clueless.app without Xcode (Command Line Tools are enough).
#   ./scripts/make_app.sh          build + bundle into build/Clueless.app
#   ./scripts/make_app.sh run      ...and launch it, logging to .run/app.log
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
# CLUELESS_ROOT (set by check.sh) says where models/ and .run/ live when building from another working copy.
swift build -c release --product Clueless
APP="build/Clueless.app"
mkdir -p "$APP/Contents/MacOS" .run
cp .build/release/Clueless "$APP/Contents/MacOS/Clueless"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.clueless.app</string>
  <key>CFBundleName</key><string>Clueless</string>
  <key>CFBundleExecutable</key><string>Clueless</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Clueless transcribes your side of a call on this Mac. Audio never leaves the device.</string>
  <key>NSCameraUsageDescription</key><string>Clueless uses the camera on this Mac to notice when you look away, so it can catch you up.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Clueless reads your screen and system audio on this Mac to answer questions about them.</string>
  <key>LSEnvironment</key><dict><key>CLUELESS_ROOT</key><string>${CLUELESS_ROOT:-$ROOT}</string></dict>
</dict></plist>
PLIST
# Ad-hoc signature, no sandbox (the app talks to localhost servers).
# By default an ad-hoc signature's designated requirement is the binary's hash, so macOS treats every
# rebuild as a new app and drops Screen Recording / Microphone / Camera permission. Pinning the
# requirement to the bundle identifier keeps the permission across rebuilds.
codesign --force --sign - --identifier com.clueless.app \
  --requirements '=designated => identifier "com.clueless.app"' "$APP"
echo "built $APP"
if [ "$1" = "run" ]; then
  pkill -x Clueless 2>/dev/null || true
  open --stderr "${CLUELESS_ROOT:-$ROOT}/.run/stderr.log" "$APP"
  echo "launched; log: .run/app.log"
fi
