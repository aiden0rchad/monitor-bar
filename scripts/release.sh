#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build.sh

# File Provider can reattach Finder metadata in synced project folders.
release_dir=$(mktemp -d "${TMPDIR:-/tmp}/monitorbar-release.XXXXXX")
trap 'rm -rf "$release_dir"' EXIT
app="$release_dir/Monitor Bar.app"
ditto --norsrc --noextattr "build/Monitor Bar.app" "$app"
xattr -cr "$app"
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/MonitorBar"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid release version: %s\n' "$version" >&2
    exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$plist")" == local.monitorbar.app ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$plist")" == 13.0 ]]
cmp LICENSE "$app/Contents/Resources/LICENSE"
[[ "$(xcrun lipo -archs "$binary")" == arm64 ]]
[[ "$(xcrun vtool -show-build "$binary" | awk '$1 == "minos" { print $2 }')" == 13.0 ]]
codesign --verify --deep --strict "$app"

mkdir -p dist
archive="Monitor-Bar-$version-arm64.zip"
ditto -c -k --keepParent --norsrc "$app" "dist/$archive"
unzip -tq "dist/$archive"
(cd dist && shasum -a 256 "$archive" > SHA256SUMS)
printf '%s\n' "Release: $PWD/dist/$archive" "Checksums: $PWD/dist/SHA256SUMS"
