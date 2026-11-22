#!/bin/bash
# Builds SecondBar.app from Sources/ into build/. No Xcode project and no signing
# identity needed: an ad-hoc signature is enough for local use.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/SecondBar.app
ARCH=$(uname -m)
MIN=27.0
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
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local build</string>
</dict>
</plist>
PLIST

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

codesign --force --sign "SecondBar Dev" "$APP" >/dev/null 2>&1 || {
  echo "warning: signing with 'SecondBar Dev' failed, falling back to ad-hoc"
  echo "         (run ./make-identity.sh so the Accessibility grant survives rebuilds)"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
}
codesign --verify --strict "$APP" >/dev/null 2>&1 && echo "signature: ok"
echo "built: $APP"
