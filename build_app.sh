#!/bin/zsh
# Builds ClearText.app (release) next to this script.
set -e
cd "$(dirname "$0")"
mkdir -p .build
swiftc -O -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" Sources/ClearText/*.swift -o .build/ClearText
APP=ClearText.app
BUILT=$(date "+%Y-%m-%d %H:%M %Z")
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/ClearText "$APP/Contents/MacOS/ClearText"
[ -f Resources/ClearText.icns ] || ./make_icon.sh
cp Resources/ClearText.icns "$APP/Contents/Resources/ClearText.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClearText</string>
  <key>CFBundleDisplayName</key><string>ClearText</string>
  <key>CFBundleIdentifier</key><string>local.cleartext.app</string>
  <key>CFBundleExecutable</key><string>ClearText</string>
  <key>CFBundleIconFile</key><string>ClearText</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>$BUILT</string>
  <key>CTBuildDate</key><string>$BUILT</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Text</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.plain-text</string><string>public.text</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $PWD/$APP"
