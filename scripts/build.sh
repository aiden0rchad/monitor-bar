#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    printf '%s\n' 'Build requires an Apple silicon Mac (arm64).' >&2
    exit 1
fi
export MACOSX_DEPLOYMENT_TARGET=13.0
target=arm64-apple-macos13.0
# Sign outside File Provider folders, which can reattach Finder metadata between
# xattr cleanup and codesign. Publish the bundle only after signing succeeds.
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/monitorbar-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
app="$build_dir/Monitor Bar.app"
output_app="build/Monitor Bar.app"
mkdir -p .build build "$app/Contents/MacOS"
xcrun clang -target "$target" -std=c11 -Wall -Wextra -Werror -O2 -c Sources/DDCBridge.c -o .build/DDCBridge.o
xcrun swiftc -target "$target" -swift-version 5 -O -import-objc-header Sources/DDCBridge.h \
    Sources/*.swift .build/DDCBridge.o -framework IOKit -framework AppKit \
    -framework ServiceManagement -o "$app/Contents/MacOS/MonitorBar"
xcrun swiftc -target "$target" -swift-version 5 -O -import-objc-header Sources/DDCBridge.h \
    Sources/Models.swift Sources/EDID.swift Sources/SamsungInputState.swift Sources/Hardware.swift scripts/Probe.swift \
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
codesign --verify --strict "$app"
rm -rf "$output_app"
ditto --norsrc --noextattr "$app" "$output_app"
printf '%s\n' "Built: $PWD/$output_app"
