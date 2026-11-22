#!/bin/bash
# Copies the built app to /Applications and (re)launches it.
#
# It has to live in /Applications: on macOS 27 an app run from anywhere else can
# have its own menu bar item hidden by the very restriction it holds, so the
# arrow would disappear. Accessibility is granted per binary path, so install
# first and then grant it once.
set -euo pipefail
cd "$(dirname "$0")"

[[ -d build/SecondBar.app ]] || ./build.sh

osascript -e 'quit app "SecondBar"' >/dev/null 2>&1 || true
sleep 0.5
rm -rf /Applications/SecondBar.app
cp -R build/SecondBar.app /Applications/SecondBar.app
open /Applications/SecondBar.app
echo "installed: /Applications/SecondBar.app"
