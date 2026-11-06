#!/bin/zsh
# Builds the app and wraps it in an installer package: dist/ClearText-Installer.pkg
# Double-click the .pkg to install ClearText into /Applications.
set -e
cd "$(dirname "$0")"
./build_app.sh
VERSION=1.0
STAGE=.build/pkgroot
rm -rf "$STAGE" dist .build/component.plist
mkdir -p "$STAGE/Applications" dist
cp -R ClearText.app "$STAGE/Applications/"

# Install to /Applications even if another copy exists elsewhere (non-relocatable).
pkgbuild --analyze --root "$STAGE" .build/component.plist >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" .build/component.plist

pkgbuild --root "$STAGE" --component-plist .build/component.plist \
  --identifier local.cleartext.app --version "$VERSION" --install-location / \
  .build/ClearText.pkg >/dev/null

cat > .build/distribution.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
  <title>ClearText</title>
  <options customize="never" require-scripts="false" hostArchitectures="$(uname -m)"/>
  <domains enable_localSystem="true"/>
  <choices-outline><line choice="default"><line choice="local.cleartext.app"/></line></choices-outline>
  <choice id="default"/>
  <choice id="local.cleartext.app" visible="false"><pkg-ref id="local.cleartext.app"/></choice>
  <pkg-ref id="local.cleartext.app" version="$VERSION" onConclusion="none">ClearText.pkg</pkg-ref>
</installer-gui-script>
XML
productbuild --distribution .build/distribution.xml --package-path .build dist/ClearText-Installer.pkg >/dev/null
echo "Built $PWD/dist/ClearText-Installer.pkg"
