#!/bin/zsh
# Regenerates Resources/ClearText.icns from tools/make_icon.swift.
set -e
cd "$(dirname "$0")"
mkdir -p Resources
rm -rf .build/ClearText.iconset
swiftc -O tools/make_icon.swift -o .build/make_icon
.build/make_icon .build/ClearText.iconset
iconutil -c icns .build/ClearText.iconset -o Resources/ClearText.icns
echo "Wrote $PWD/Resources/ClearText.icns"
