#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -module-cache-path .build/module-cache Sources/ClassicPaint/*.swift -o .build/ClassicPaint
APP="$PWD/dist/Classic Paint.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/ClassicPaint "$APP/Contents/MacOS/ClassicPaint"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClassicPaint</string>
<key>CFBundleIdentifier</key><string>local.classicpaint.editor</string>
<key>CFBundleName</key><string>Classic Paint</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
ditto "$APP" "$PWD/dist/Classic Paint 0.2.app"
echo "$PWD/dist/Classic Paint 0.2.app"
