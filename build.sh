#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The SecondBar Authors
# Builds SecondBar.app from Sources/ into build/. No Xcode project needed. A stable
# self-signed identity is preferred (see make-identity.sh): an ad-hoc signature has
# no identity, and TCC remembers the Accessibility grant by identity, so an ad-hoc
# build loses the grant on every rebuild.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SecondBar.app
ARCH=${ARCH:-$(uname -m)}
MIN=27.0
VERSION=${VERSION:-1.1}
BUILD_NUMBER=${BUILD_NUMBER:-1}
# A release build has no "SecondBar Dev" identity; "-" means ad-hoc, which is what
# CI uses. Local builds keep the stable identity so the Accessibility grant holds.
IDENTITY=${CODESIGN_IDENTITY:-SecondBar Dev}
rm -rf "$APP" build/obj
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SecondBar</string>
  <key>CFBundleDisplayName</key><string>SecondBar</string>
  <key>CFBundleExecutable</key><string>SecondBar</string>
  <key>CFBundleIdentifier</key><string>local.secondbar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>SecondBar</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>__BUILD_NUMBER__</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 The SecondBar Authors</string>
</dict>
</plist>
PLIST

sed -i '' -e "s/__VERSION__/$VERSION/" -e "s/__BUILD_NUMBER__/$BUILD_NUMBER/" "$APP/Contents/Info.plist"

# The icon is generated once and kept in Assets/; regenerating needs a Swift run,
# so it is not part of every build.
if [[ ! -f Assets/SecondBar.icns ]]; then
  echo "== generating icon"
  swift tools/makeicon.swift Assets
  iconutil -c icns Assets/SecondBar.iconset -o Assets/SecondBar.icns
fi
cp Assets/SecondBar.icns "$APP/Contents/Resources/SecondBar.icns"

echo "== compiling Shim.m"
clang -fobjc-arc -fblocks -O2 -target "${ARCH}-apple-macosx${MIN}" \
  -I Sources -c Sources/Shim.m -o build/obj/Shim.o

echo "== compiling Swift"
swiftc -O -swift-version 5 \
  -target "${ARCH}-apple-macosx${MIN}" \
  -import-objc-header Sources/Bridging-Header.h \
  -o "$APP/Contents/MacOS/SecondBar" \
  Sources/*.swift build/obj/Shim.o \
  -framework AppKit -framework ApplicationServices

codesign --force --sign "$IDENTITY" "$APP" >/dev/null 2>&1 || {
  if [[ "$IDENTITY" == "-" ]]; then
    echo "error: ad-hoc signature failed"; exit 1
  fi
  echo "warning: signing with '$IDENTITY' failed, falling back to ad-hoc"
  echo "         (run ./make-identity.sh so the Accessibility grant survives rebuilds)"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
}
codesign --verify --strict "$APP" >/dev/null 2>&1 && echo "signature: ok"
echo "built: $APP"
