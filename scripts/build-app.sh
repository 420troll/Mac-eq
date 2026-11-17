#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch x86_64
APP="$PWD/dist/TROLLfx Mac EQ.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/TROLLfxMacEQ "$APP/Contents/MacOS/TROLLfxMacEQ"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TROLLfxMacEQ</string>
<key>CFBundleIdentifier</key><string>com.trollfx.maceq</string>
<key>CFBundleName</key><string>TROLLfx Mac EQ</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Created %s\n' "$APP"
echo 'To run locally: right-click the app and select Open if Gatekeeper warns about an unsigned build.'
