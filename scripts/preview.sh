#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export MACOSX_DEPLOYMENT_TARGET=13.0
report="${1:-Tests/Fixtures/demo-monitor.json}"
if [[ ! -f "$report" ]]; then
    printf 'Missing monitor report: %s\n' "$report" >&2
    exit 1
fi
mkdir -p .build/preview
clang -target arm64-apple-macos13.0 -std=c11 -Wall -Wextra -Werror -O2 -c Sources/DDCBridge.c -o .build/DDCBridge-preview.o
# Keep the real panel implementation, but give the offline renderer the entry point.
awk '!/^[[:space:]]*@main[[:space:]]*$/' Sources/MonitorBarApp.swift > .build/PreviewUI.swift
sources=()
for source in Sources/*.swift; do
    [[ "$source" == Sources/MonitorBarApp.swift ]] || sources+=("$source")
done
swiftc -target arm64-apple-macos13.0 -swift-version 5 -O -import-objc-header Sources/DDCBridge.h \
    "${sources[@]}" .build/PreviewUI.swift scripts/RenderPanel.swift \
    .build/DDCBridge-preview.o -framework IOKit -framework AppKit \
    -framework ServiceManagement -framework UniformTypeIdentifiers -o .build/render-panel
.build/render-panel "$report"
