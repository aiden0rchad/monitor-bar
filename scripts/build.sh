#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'Build requires an Apple silicon Mac (arm64).' >&2
    exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=13.0
target=arm64-apple-macos13.0
app="build/Monitor Bar.app"
rm -rf "$app"
mkdir -p .build "$app/Contents/MacOS"
xcrun clang -target "$target" -std=c11 -Wall -Wextra -Werror -O2 -c Sources/DDCBridge.c -o .build/DDCBridge.o
xcrun swiftc -target "$target" -swift-version 5 -O -import-objc-header Sources/DDCBridge.h \
    Sources/*.swift .build/DDCBridge.o -framework IOKit -framework AppKit \
    -framework ServiceManagement -o "$app/Contents/MacOS/MonitorBar"
xcrun swiftc -target "$target" -swift-version 5 -O -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/Hardware.swift scripts/Probe.swift \
    .build/DDCBridge.o -framework IOKit -framework AppKit -o .build/monitor-probe
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
fi
# Finder metadata can invalidate signatures in synced folders.
xattr -cr "$app"
codesign --force --sign - "$app"
printf '%s\n' "Built: $PWD/$app"
